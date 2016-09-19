#!/bin/bash
#
# Entrypoint script for Load Generator Docker Image
set -e

case "${RUN}" in
  stress)
    [[ "${STRESS_CPU}" ]] && STRESS_CPU="--cpu ${STRESS_CPU}"
    [[ "${STRESS_TIME}" ]] && STRESS_TIME="--timeout ${STRESS_TIME}"
    exec stress ${STRESS_CPU} ${STRESS_TIME}
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
    [[ "${ROUTER_IP}" ]] && echo "${ROUTER_IP} ${TARGET_HOST}" >> /etc/hosts

    # Wait for Cluster Loader start signal webservice
    while [[ -z $(curl -s http://"${GUN}":9090) ]]; do sleep 5; echo "not ready"; done
    results_filename=jmeter-"${HOSTNAME}"-"$(date +%y%m%d%H%M)" 

    # Call JMeter packed with ENV vars
    jmeter -n -t test.jmx -Jnum=${NUM} -Jramp=${JMETER_RAMP} \
      -Jduration=${JMETER_TIME} -Jtpm=${JMETER_TPS} -Jipaddr1=${TARGET[0]} \
      -Jipaddr2=${TARGET[1]} -Jipaddr3=${TARGET[2]} -Jipaddr4=${TARGET[3]} \
      -Jipaddr5=${TARGET[4]} -Jipaddr6=${TARGET[5]} -Jipaddr7=${TARGET[6]} \
      -Jipaddr8=${TARGET[7]} -Jipaddr9=${TARGET[8]} -Jport=${TARGET_PORT} \
      -Jresults_file="${results_filename}".jtl -l "${results_filename}".jtl \
      -j "${results_filename}".log -Jgun=${GUN}

    # Find PBench directory
    pbench_dir=$(ssh "${GUN}" 'cd /var/lib/pbench-agent && cd pb*/. && pwd')
    if [[ "${pbench_dir}" == *pbench-user-benchmark* ]]; then
      # Copy results back to Cluster Loader host in PBench dir
      scp *.jtl *.log *.png ${GUN}:${pbench_dir}
    fi
    ;;
  *)
    echo "Need to specify what to run."
    ;;
esac

