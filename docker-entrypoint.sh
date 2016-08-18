#!/bin/bash
#
# Entrypoint script for Load Generator Docker Image
set -e

case "${RUN}" in
  stress)
    [[ "${STRESS_CPU}" ]] && STRESS_CPU="--cpu ${STRESS_CPU}"
    [[ "${STRESS_TIME}" ]] && STRESS_TIME="--timeout ${STRESS_TIME}"
    exec stress "${STRESS_CPU}" "${STRESS_TIME}"
    ;;
  jmeter)
    IFS=$'\n' 
    TARGET=($(echo $TARGET_HOST | sed 's/\:/\n/g'))
    TARGET_HOST="$(echo $TARGET_HOST | sed 's/\:/\ /g')"
    NUM="$(echo $TARGET_HOST | wc -w)"
    [[ "${ROUTER_IP}" ]] && echo "${ROUTER_IP} ${TARGET_HOST}" >> /etc/hosts

    while [[ -z $(curl -s http://"${GUN}":9000) ]]; do sleep 5; echo "not ready"; done
    jmeter -n -t test.jmx -Jnum=${NUM} -Jramp=${JMETER_RAMP} \
      -Jduration=${JMETER_TIME} -Jtps=${JMETER_TPS} -Jipaddr1=${TARGET[0]} \
      -Jipaddr2=${TARGET[1]} -Jipaddr3=${TARGET[2]} -Jipaddr4=${TARGET[3]} \
      -Jipaddr5=${TARGET[4]} -Jipaddr6=${TARGET[5]} -Jipaddr7=${TARGET[6]} \
      -Jipaddr8=${TARGET[7]} -Jipaddr9=${TARGET[8]} -Jport=${TARGET_PORT} \
      -l jmeter-"${HOSTNAME}"-"$(date +%y%m%d%H%M)".jtl -j jmeter-"${HOSTNAME}"-"$(date +%y%m%d%H%M)".log
    scp *.jtl *.log ${GUN}:/tmp/
    ;;
  *)
    echo "Need to specify what to run."
    ;;
esac

