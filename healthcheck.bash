#!/usr/bin/env bash
#
##############################
#This script monitors a given service and restarts it in case of failures.
#NOTE: It must be run with sudo to give it access to systemctl.
##############################
#
#make sure we exit if a command were to fail
set -o errexit

#ensure every variable is declared
set -o nounset

#catch errors downstream from a pipe
set -o pipefail

#-------------initialize the constants----------
readonly SLEEP_TIME=1 #time between checks in seconds
readonly URL="http://localhost/healthcheck" #the URL to check
readonly FAIL_CODE='FAIL(500)' #failure string. This can be relaxed to just 5 to grab all 5xx errors.
readonly MAX_FAILURES=5  #max failures before restart
readonly SERVICE='foobar.service' #the name of the service to health check
#-----------------------------------------------

#get the full path of the script for logging purposes
SCRIPT_NAME=$(readlink -fn $BASH_SOURCE)

#make sure the necessary utilities are present in the $PATH.
#Use command -v to make the check POSIX compliant,
#since "which" return codes are not guaranteed!
command -v curl >/dev/null || { echo "ERROR: curl is not in the $PATH. Exiting."; exit 1; }
command -v systemctl >/dev/null || { echo "ERROR: systemctl is not in the $PATH. Exiting."; exit 1; }

_check_health () {
	#This function accepts a single parameter, the URL to check.
	#The parameter goes into $1 and is immediately assigned to url for checking
	local url="$1"

	#run curl with the silent option to suppress unnecessary output
	local curlValue=$(curl --silent "$url")

	#return the value from the curl call above
	echo "$curlValue"
}

#initialize the total failures counter.
#Note: we are setting it to 1 so that when the MAX_FAILURES comparison happens,
#the restart takes place at MAX_FAILURES. Otherwise, we go over by 1.
totalFailures=1

#get the infinite loop going
while :
do
	#first, call the _check_health function to get the endpoint return value
	healthValue=$(_check_health $URL)

	#some debugging statements
	#echo "health is $healthValue"
	#echo "failed counter is $totalFailures"

	#we have 1 value but case is a nice, POSIX-compliant way to check for string in a string
	case "$healthValue" in
		*${FAIL_CODE}*)
		totalFailures=$((totalFailures + 1))
		;;
	esac

	#see if we have exceeded the total max failures allowed
	if [[ $totalFailures > $MAX_FAILURES ]];
	then
		#log to syslog
		logger "${SCRIPT_NAME}: $SERVICE is experiencing too many failures, attempting to restart!"

		#restart the service
		systemctl restart $SERVICE

		#log in case of failures
		if [ $? -ne 0 ]; then
			logger "${SCRIPT_NAME}: Restart of $SERVICE failed!"
		fi

		#reset the counter back to 1
		totalFailures=1
	fi

	#sleep until the next run
	sleep $SLEEP_TIME
done
