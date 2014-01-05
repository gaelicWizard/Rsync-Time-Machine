#!/bin/bash
set -e # die on error

# DO NOT EDIT THIS IN /etc/init.d! Edit the one in /JewishRiverside and then $ sudo cp /JewishRiverside/backup.bash /etc/init.d/backupl

###
## This script fully replaces the prior backup script. It creates dated, incremental, sparse backups under /backups. 
## This script is meant to be adapted for remote backups readily. In fact, simply adding to destinationRoots a remote target will make it magic.
## Currently, thinning old backups is not implemented. This won't be a problem for a long while, since the backups are sparse. 
###
## To run this script just once, do `sudo /JewishRiverside/backup.bash once`. It will not loop. This is useful for troubleshooting.
###


###
## CONFIGURATION
###


INTERVAL=1h

destinationRoots=(
	/backups										#TODO: /Backups.backupdb
#	"dabahc@JewishRiverside-bu.no-ip.org:backup/"	#TODO: Ensure that the remote backup machine has a symlink at ~/backup pointing to the backup root.
)

sourceRoots=(
	/JewishRiverside
)





###
## DO NOT EDIT BELOW HERE
###













#

readonly PROJECT="Rsync Time Machine"
readonly SELF="${0##*/}"
readonly ME="$SELF[$$]"

readonly sourceRoots destinationRoots


## TODO: trap signals for cleanup, thinning, immutable archives, proper Sys-V init interaction (start, restart, stop, &c.) (see /etc/init.d/skeleton), ...

function main ()
# The main() function is allowed to use globals. Others aren't. handle_rsync_error and post_backup_thinning fail due to poor flow control in main().
{
	if [ x"$1" == x"once" ]
	then
		INTERVAL=never
		# This setting is meant to make the `sleep` invokation fail, preventing the loop from continuing.
		set start now # discard arguments, set new args.
	fi
	readonly INTERVAL="${INTERVAL:-1h}"

	if [ x"$1" != x"start" ]
	then
		echo "$ME: This script is meant to be started from a SysV-style init system (use a 'start' argument)." 1>&2
		exit 1
	fi
	shift # discard "start" argument

	echo $$ > /var/run/RsyncTimeMachine.pid

	logfile=/var/log/RsyncTimeMachine.log
	echo "$ME: Logging to $logfile." 1>&2
	exec >> $logfile 2>&1 # Redirect _both_ stdout and stderr.
	exec < /dev/null # disassociate from tty

	echo ""
	echo "$ME: $PROJECT starting." 1>&2

	while { { [ "now" == "$1" ] && { verbose=v; shift; }; } ||  sleep $INTERVAL 2>/dev/null; }
	do
		local loopDate="$(date)"
		echo "$ME: Beginning backup loop iteration ($loopDate)." 1>&2

		#rsyncTimeMachineInto:fromRoot: "${destinationRoots[0]}" "${sourceRoots[0]}"
		rsyncTimeMachineInto:BackupDBs:from:Roots: "${#destinationRoots[@]}" "${destinationRoots[@]}" "${#sourceRoots[@]}" "${sourceRoots[@]}"

		#post_backup_thinning "${destinationRoots[0]}"

		echo "$ME: Completed backup loop iteration ($loopDate)." 1>&2
		unset verbose # only useful for first iteration...
	done

	echo "$ME: $PROJECT exiting." 1>&2
	exit
}

function rsyncTimeMachineInto:BackupDBs:from:Roots: ()
##
# This function takes two variable-size sets of arguments. Make sure to pass the count of each prior to the elements. 
##
{
	local -ir	numberOfBackupDBs="$1"; shift
	local -a	BackupDBs
	local -i	i=0
	while (( i++ < numberOfBackups ));
	do
		BackupDBs[${#BackupDBs}]="$1"; shift
	done
	readonly BackupDBs

	local -ir	numberOfSourceRoots="$1"; shift
	local -a	SourceRoots
	local -i	i=0
	while (( i++ < numberOfSourceRoots ));
	do
		SourceRoots[${#SourceRoots}]="$1"; shift
	done
	readonly SourceRoots

	local eachBackupDB
	for eachBackupDB in "${BackupDBs[@]}"
	do
		#pre_backup_thinning "${eachBackupDB}" 5GB
		rsyncTimeMachineInto:fromRoots: "${eachBackupDB}" "${SourceRoots[@]}"
		#post_backup_thinning "${eachBackupDB}" 5GB
	done
}

function rsyncTimeMachineInto:fromRoots: ()
{
	local -r destinationBackupDB="$1"
	shift
	local eachRoot=

	for eachRoot in "$@"
	do
		rsyncTimeMachineInto:fromRoot: "$destinationBackupDB" "$eachRoot"
	done
}

function rsyncTimeMachineInto:fromRoot: ()
{
	local -r	destinationBackupDB="${1:-/dev/null}" \
						 sourceRoot="${2:-/dev/null}"

	local -r	localHostname="$(hostname -s)"
	local -r	newDate=$(date +%FT%H:%M:%SZ)
	local		sourceName="$(basename "$sourceTarget")"
				[ "/" == "$sourceName" ] && sourceName=Root; readonly sourceName
	local -r	destinationTargetForHost="$destinationBackupDB"/"$localHostname"
	local -r	destinationTargetWithDate="$destinationTargetForHost"/"$newDate"
	local -r	destinationTarget="$destinationTargetWithDate"/"$sourceName"

	#TODO: unlock $destinationTargetWithDate in order to create $destinationTarget.

	(set -x # Log the actual command(s) used.
	mkdir -m 0755 "$destinationTargetWithDate"
	exec rsync -ahxyz${verbose:-}				\
			--exclude="/.recycle" 					\
			--exclude="/lost+found" 				\
			--link-dest="../Latest"					\
				"$sourceRoot/"						\
				"$destinationTarget/"
	) || handle_rsync_error "$?"

	#archive_backup "$destinationTarget" #TODO: lock ...WithDate too.

	ln -fnsv "$perDate" "$destinationTargetForHost"/Latest
}

function handle_rsync_error ()
{
	rsyncDidSucceed=false
	if [ 23 == "$1" ]; then
		echo "It appears that `rsync` reported a partial backup (error ($1)). This is most likely due to missing files or improper privileges. We are NOT aborting." 1>&2 
		return 0
	fi

	return $1 # real error
}

function archive_backup ()
# This function locks down the backup to prevent it from being damaged. 
{
	###
	## DOES NOT WORK. 
	## Linux ACLs are unable to specify 'immutable' and the immutable filesystem flag cuases hardlinks to fail. There is no current solution on linux to archive backups non-destructively. A destructive alternative is to chmod -R a-w ..., but this is reversible by the owner so chown root would be needed...
	## Something could be written to *un-immitable* the most recent archive during the backup process, but that's nasty.
	## maybe write something that leaves *nix permissions intact but adds an explicit "owner" ACL (as well as a mask) that prevents alteration...
	###
	
	
	local target="$1"
	echo "NOT Archiving backup at $target..."
	#setfacl
	#chattr -R +i "$target"
		# Recursively set *all* files immutable.
}

function post_backup_thinning ()
# This function [should/will] implements policy as to which backups to keep.
{
	# Current Policy: 	keep one backup per calendar month forever; 
	#					keep one backup every day this year, prior to the current month;
	#					keep one backup every hour this month, prior to the current day;
	#					keep all backups from the current day.
	#					(This assumes that the backup interval is six (6) minutes or similar, which is *very* frequent.)
	
	## CURRENT LIMITATION: Datemath is hard. So, I use calendar years, months, days, and hours. The policy is liberal enough that there should never be too *little*, but there will frequently be way too much. E.G., when run on YYYY:01:01T00:06:00Z, a huge amount of history will be deleted and the immediately prior backup will be a month old, but the current backup will have already been successful. 
	
	if [ "true" != "$rsyncDidSucceed" ]; then
		echo "Skipping post-backup thinning." 1>&2
		return
	fi
	
	local 	currentYear="$(date +%Y)" \
			currentMonth="$(date +%m)"

	echo "Beginning post-backup thinning..." 1>&2

	# for each year
	# 	exclude current year
	# 	for each year-month
	# 		exclude first month entry
	#  		delete all year-month-*
	# for current year
	#	exclude current month
	#	for each year-month-day
	#		exclude first day entry
	#		delete all year-month-day-*
	# for current year-month
	#	exclude current day
	#	for each year-month-day-hour
	#		exclude first hour entry
	#		delete all year-month-day-hour-*
	
	echo "Completed post-backup thinning." 1>&2
}

function logit ()
{
	echo "$ME: $@" 
	#| tee -ai
}

main "$@" # never returns
