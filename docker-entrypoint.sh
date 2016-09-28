#!/bin/bash
# Some parts written for /bin/bash, see arrays in jmeter)
# Entrypoint script for Load Generator Docker Image

ProgramName=${0##*/}

# Global variables
url_gun_ws="http://${GUN}:9090"
gw_hex=$(grep ^eth0 /proc/net/route | head -1 | awk '{print $3}')
#gateway=$(/sbin/ip route|awk '/default/ { print $3 }')	# sometimes there is no /sbin/ip ...
gateway=$(printf "%d.%d.%d.%d" 0x${gw_hex:6:2} 0x${gw_hex:4:2} 0x${gw_hex:2:2} 0x${gw_hex:0:2})

fail() {
  echo $@ >&2
}

warn() {
  fail "$ProgramName: $@"
}

die() {
  local err=$1
  shift
  fail "$ProgramName: $@"
  exit $err
}

usage() {
  cat <<EOF 1>&2
Usage: $ProgramName
EOF
}

have_server() {
  local server="$1"
  if test "${server}" = "127.0.0.1" || test "${server}" = "" ; then
    # server not defined
    return 1
  fi 
}

# Wait for all the pods to be in the Running state
synchronize_pods() {
  have_server "${GUN}" || return

  while [ -z $(curl -s "${url_gun_ws}") ] ; do 
    sleep 5
    fail "${url_gun_ws} not ready"
  done
}

# basic checks for toybox/busybox/coreutils timeout
define_timeout_bin() {
  test "${RUN_TIMEOUT}" || return	# timeout empty, do not define it and just return

  timeout -t 0 /bin/sleep 0 >/dev/null 2>&1

  case $? in
    0)   # we have a busybox timeout with '-t' option for number of seconds
       timeout="timeout -t ${RUN_TIMEOUT}"
    ;;
    1)   # we have toybox's timeout without the '-t' option for number of seconds
       timeout="timeout ${RUN_TIMEOUT}"
    ;;
    125) # we have coreutil's timeout without the '-t' option for number of seconds
       timeout="timeout ${RUN_TIMEOUT}"
    ;;
    *)   # couldn't find timeout or unknown version
       warn "running without timeout"
       timeout=""
    ;;
  esac
}

timeout_exit_status() {
  local err="${1:-$?}"

  case $err in
    124) # coreutil's return code for timeout
       return 0
    ;;
    143) # busybox's return code for timeout with default signal TERM
       return 0
    ;;
    *) return $err
  esac
}

main() {
  define_timeout_bin

  case "${RUN}" in
    stress)
      synchronize_pods
 
      [ "${STRESS_CPU}" ] && STRESS_CPU="--cpu ${STRESS_CPU}"
      $timeout \
        stress ${STRESS_CPU}
      $(timeout_exit_status) || die $? "${RUN} failed: $?"
      ;;

    slstress)
      local slstress_log=/tmp/${HOSTNAME}-${gateway}.log

      synchronize_pods
      $timeout \
        slstress \
          -l ${LOGGING_LINE_LENGTH} \
          -w \
          ${LOGGING_DELAY} > ${slstress_log}
      $(timeout_exit_status) || die $? "${RUN} failed: $?"

      if have_server "${PBENCH_HOST}" ; then
        scp -p ${slstress_log} ${PBENCH_HOST}:${PBENCH_DIR}
      fi
    ;;

    logger)
      local slstress_log=/tmp/${HOSTNAME}-${gateway}.log

      synchronize_pods
      $timeout \
        /usr/local/bin/logger.sh
      $(timeout_exit_status) || die $? "${RUN} failed: $?"
    ;;

    jmeter)
      IFS=$'\n' 
      # Massage the host data passed in from OSE
      TARGET=($(echo $TARGET_HOST | sed 's/\:/\n/g'))
      TARGET_HOST="$(echo $TARGET_HOST | sed 's/\:/\ /g')"
      NUM="$(echo $TARGET_HOST | wc -w)"
      # JMeter constant throughput times wants TPM
      ((JMETER_TPS*=60))

      # Add router IP & hostnames to hosts file
      [ "${ROUTER_IP}" ] && echo "${ROUTER_IP} ${TARGET_HOST}" >> /etc/hosts

      # Wait for Cluster Loader start signal webservice
      synchronize_pods
      results_filename=jmeter-"${HOSTNAME}"-"$(date +%y%m%d%H%M)" 

      # Call JMeter packed with ENV vars
      jmeter -n -t test.jmx -Jnum=${NUM} -Jramp=${JMETER_RAMP} \
        -Jduration=${RUN_TIME} -Jtpm=${JMETER_TPS} -Jipaddr1=${TARGET[0]} \
        -Jipaddr2=${TARGET[1]} -Jipaddr3=${TARGET[2]} -Jipaddr4=${TARGET[3]} \
        -Jipaddr5=${TARGET[4]} -Jipaddr6=${TARGET[5]} -Jipaddr7=${TARGET[6]} \
        -Jipaddr8=${TARGET[7]} -Jipaddr9=${TARGET[8]} -Jport=${TARGET_PORT} \
        -Jresults_file="${results_filename}".jtl -l "${results_filename}".jtl \
        -j "${results_filename}".log -Jgun="${GUN}" || die $? "${RUN} failed: $?"

      have_server "${PBENCH_HOST}" && scp -p *.jtl *.log *.png ${PBENCH_HOST}:${PBENCH_DIR}
    ;; 

    *)
      die 1 "Need to specify what to run."
    ;;
  esac
  timeout_exit_status
}

main
