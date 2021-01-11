#!/bin/bash
scriptroot=$(dirname $(realpath $0))

# Check dependencies
deps=("printf|fprintd" "setcd|setcd" "sed|sed" "blkid|util-linux" "dd|coreutils")
missingdeps=""
missingdepsinstall="sudo apt install"

for dep in "${deps[@]}"; do
	if ! type $(echo "$dep" | cut -d\| -f1) &> /dev/null; then
		missingdeps=$(echo "$missingdeps$(echo "$dep" | cut -d\| -f1), ")
		missingdepsinstall=$(echo "$missingdepsinstall $(echo "$dep" | cut -d\| -f2)")
	fi
done
if [ -n "$missingdeps" ]; then
	echo "[ERROR] Missing dependencies! ($(echo "$missingdeps" | xargs | sed 's/.$//'))"
	echo "        You can install them using this command:"
	echo "        ----------------------------------------"
	echo "        $missingdepsinstall"
	echo "        ----------------------------------------"
	exit 1
fi

# Initial search for drives
drives=($(ls /dev/sr*))
echo "----------------------------"
printf "Found the following devices:\n$(printf '%s\n' "${drives[@]}")\n"
echo "----------------------------"

# Create template for forking
discstatus () {
	while true; do
		# Getting the current disc status
		discinfo=$(setcd -i "$drive" 2> /dev/null)

		case "$discinfo" in
			# What to do when the disc is found and ready
			*'Disc found'*)
				echo "[INFO] $drive: disc is ready" >&2;
				unset repeatnodisc;
				unset repeatemptydisc;
				/bin/bash $scriptroot/isorip.sh "$drive";
				sleep 2;
				eject $drive;
				sleep 10;
				;;
			# What to do when the disc is found, but not yet ready
			*'not ready'*)
				echo "[INFO] $drive: waiting for drive to be ready" >&2;
				unset repeatemptydisc;
				sleep 5;
				;;
			# What to do when the drive tray is open
			*'is open'*)
				if [[ $repeatemptydisc -lt 3 ]]; then
					echo "[INFO] $drive: drive is open" >&2
					repeatemptydisc=$((repeatemptydisc+1))
				fi;
				sleep 5;
				;;
			# What to do when the drive tray is closed, but no disc was recognized
			*'No disc is inserted'*)
				if [[ $repeatnodisc -lt 3 ]]; then
					echo "[WARN] $drive: drive tray is empty" >&2
					repeatnodisc=$((repeatnodisc+1))
				fi;
				unset repeatemptydisc;
				sleep 15;
				;;
			*)
			# What to do when none of the above was the case
				echo "[ERROR] $drive: Confused by setcd -i, bailing out" >&2;
				unset repeatemptydisc;
				eject $drive;
		esac
	done
}

# Start parallelized jobs for every drive found
for drive in "${drives[@]}"; do discstatus "$drive" & done

# Wait for all jobs to be finished (which will never be the case), but this way you can actually stop the script using "CRTL + C"
wait < <(jobs -p)
