#!/bin/bash
#
# Entrypoint script for Load Generator Docker Image
set -e

start_time=$(echo "$(date -d "5 minutes" "+%Y%m%d%H%M%S") - ($(date +%s)%60)" | bc)

case "${RUN}" in
  stress)
    [[ "${STRESS_CPU}" ]] && STRESS_CPU="--cpu ${STRESS_CPU}"
    [[ "${STRESS_TIME}" ]] && STRESS_TIME="--timeout ${STRESS_TIME}"
    exec stress "${STRESS_CPU}" "${STRESS_TIME}"
    ;;
  jmeter)
    IFS=$'\n' 
    TARGET=($(echo $TARGET_IP | sed 's/\:/\n/g'))
    TARGET_IP="$(echo $TARGET_IP | sed 's/\:/\ /g')"
    NUM="$(echo $TARGET_IP | wc -w)"
    [[ "${ROUTER_IP}" ]] && echo "${ROUTER_IP} ${TARGET_IP}" >> /etc/hosts

    while [[ $(date -d "+%Y%m%d%H%M%S") -lt ${start_time} ]]; do sleep 5; done
    exec jmeter -n -t test.jmx -Jnum=${NUM} -Jramp=${JMETER_RAMP} \
      -Jduration=${JMETER_TIME} -Jtps=${JMETER_TPS} -Jipaddr1=${TARGET[0]} \
      -Jipaddr2=${TARGET[1]} -Jipaddr3=${TARGET[2]} -Jipaddr4=${TARGET[3]} \
      -Jipaddr5=${TARGET[4]} -Jipaddr6=${TARGET[5]} -Jipaddr7=${TARGET[6]} \
      -Jipaddr8=${TARGET[7]} -Jipaddr9=${TARGET[8]} -Jport=${TARGET_PORT}
    ;;
  *)
    echo "Need to specify what to run."
    ;;
esac

