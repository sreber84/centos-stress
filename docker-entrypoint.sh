#!/bin/bash
# Some parts written for /bin/bash, see arrays in jmeter
# Entrypoint script for Load Generator Docker Image

ProgramName=${0##*/}

# Global variables
pctl_bin=pctl
url_gun_ws="http://${GUN}:9090"
gw_hex=$(grep ^eth0 /proc/net/route | head -1 | awk '{print $3}')
#gateway=$(/sbin/ip route|awk '/default/ { print $3 }')	# sometimes there is no /sbin/ip ...
gateway=$(printf "%d.%d.%d.%d" 0x${gw_hex:6:2} 0x${gw_hex:4:2} 0x${gw_hex:2:2} 0x${gw_hex:0:2})
JVM_ARGS=${JVM_ARGS:--Xms512m -Xmx4096m}	# increase heap size by default

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

  while [ "$(curl -s ${url_gun_ws}/gotime/start)" != "GO" ] ; do 
    sleep 5
    fail "${url_gun_ws} not ready"
  done
}

announce_finish() {
  have_server "${GUN}" || return

  curl -s ${url_gun_ws}/gotime/finish
}

get_cfg() {
  local path="$1"
  curl -Ls "${url_gun_ws}/${path}"
}

# basic checks for toybox/busybox/coreutils timeout
define_timeout_bin() {
  test "${RUN_TIME}" || return	# timeout empty, do not define it and just return

  timeout -t 0 /bin/sleep 0 >/dev/null 2>&1

  case $? in
    0)   # we have a busybox timeout with '-t' option for number of seconds
       timeout="timeout -t ${RUN_TIME}"
    ;;
    1)   # we have toybox's timeout without the '-t' option for number of seconds
       timeout="timeout ${RUN_TIME}"
    ;;
    125) # we have coreutil's timeout without the '-t' option for number of seconds
       timeout="timeout ${RUN_TIME}"
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
    137) # timeout also sends SIGKILL if a process fails to respond
       return 0
    ;;
    143) # busybox's return code for timeout with default signal TERM
       return 0
    ;;
    *) return $err
  esac
}

graph_total_latency_pctl() {
  local results="$1"
  local dir_out="$2"
  local graph_conf=$(realpath total_latency_pctl.conf)
  local graph_data_in_latency=$dir_out/total_latency_pctl.txt
  local graph_image_out=$dir_out/total_latency_pctl.png
 
  mkdir -p $dir_out
  rm -f $graph_data_in_latency
  for err in $(awk -F, '{print $2}' $results | sort -u)
  do
    printf "%s\t" $err >> $graph_data_in_latency
    awk -F, "{if(\$2 == $err) {print (\$3/1000000)}}" < $results  | \
      $pctl_bin >> $graph_data_in_latency
  done
  
  gnuplot \
    -e "data_in='$graph_data_in_latency'" \
    -e "graph_out='$graph_image_out'" \
    $graph_conf
}

graph_time_bytes_hits_latency() {
  local results="$1"
  local dir_out="$2"
  local graph_data_in=$dir_out/time_bhl.txt

  local graph_bytes_conf=$(realpath time_bytes.conf)
  local graph_image_out_bytes=$dir_out/time_bytes.png

  local graph_hits_conf=$(realpath time_hits.conf)
  local graph_image_out_hits=$dir_out/time_hits.png

  local graph_latency_conf=$(realpath time_latency.conf)
  local graph_image_out_latency=$dir_out/time_latency.png

  mkdir -p $dir_out
  cat $results | LC_ALL=C sort -t, -n -k1 | \
  awk '
{
  time=int($1/1000000000)
  latency += ($3/1000000)
  bytes_out += $4
  bytes_in += $5
  hits += 1
  if(time_prev == 0) {
    time_prev=time	# we are just beginning
  }
  if(time_prev != time) {
    printf "%ld\t%ld\t%ld\t%ld\t%lf\n", time_prev, bytes_out, bytes_in, hits, (latency/hits)
    time_prev=0
    bytes_out=0
    bytes_in=0
    hits=0
    latency=0
  }
} 
BEGIN {
  FS=","
  time_prev=0
  bytes_out=0
  bytes_in=0
  hits=0
  latency=0
}
' > $graph_data_in

  gnuplot \
    -e "data_in='$graph_data_in'" \
    -e "graph_out='$graph_image_out_bytes'" \
    $graph_bytes_conf

  gnuplot \
    -e "data_in='$graph_data_in'" \
    -e "graph_out='$graph_image_out_hits'" \
    $graph_hits_conf

  gnuplot \
    -e "data_in='$graph_data_in'" \
    -e "graph_out='$graph_image_out_latency'" \
    $graph_latency_conf
}

main() {
  define_timeout_bin
  synchronize_pods

  case "${RUN}" in
    stress)
      [ "${STRESS_CPU}" ] && STRESS_CPU="--cpu ${STRESS_CPU}"
      $timeout \
        stress ${STRESS_CPU}
      $(timeout_exit_status) || die $? "${RUN} failed: $?"
      ;;

    slstress)
      local slstress_log=/tmp/${HOSTNAME}-${gateway}.log

      $timeout \
        slstress \
          -l ${LOGGING_LINE_LENGTH} \
          -w \
          ${LOGGING_DELAY} > ${slstress_log}
      $(timeout_exit_status) || die $? "${RUN} failed: $?"

      if have_server "${GUN}" ; then
        scp -p ${slstress_log} ${GUN}:${PBENCH_DIR}
      fi
    ;;

    logger)
      local slstress_log=/tmp/${HOSTNAME}-${gateway}.log

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

      local ips=""
      local i=0
      while test $i -lt $NUM ; do
        ips=${ips}$'\n'"-Jipaddr$(($i+1))=${TARGET[$i]}"
        i=$((i+1))
      done

      # Wait for Cluster Loader start signal webservice
      results_filename=jmeter-"${HOSTNAME}"-"$(date +%y%m%d%H%M)" 

      # Call JMeter packed with ENV vars
      jmeter -n -t test.jmx -Jnum=${NUM} -Jramp=${JMETER_RAMP} \
        -Jduration=${RUN_TIME} -Jtpm=${JMETER_TPS} \
        ${ips} \
        -Jport=${TARGET_PORT} \
        -Jresults_file="${results_filename}".jtl -l "${results_filename}".jtl \
        -j "${results_filename}".log -Jgun="${GUN}" || die $? "${RUN} failed: $?"

      have_server "${GUN}" && scp -p *.jtl *.log *.png ${GUN}:${PBENCH_DIR}
    ;; 

    vegeta)
      local vegeta_log=/tmp/${HOSTNAME}-${gateway}.log
      local rate=5000			# rate of client requests [s] (per all targets; i.e. /#targets per target)
      local requests_timeout=30s	# Requests timeout
      local idle_connections=20000
      local dir_test=./
      local targets_awk=targets.awk
      local targets_lst=$dir_test/targets-${IDENTIFIER}.txt
      local latency_html=$dir_test/latency-${IDENTIFIER}.html
      local results_bin=$dir_test/results-${IDENTIFIER}.bin
      local results_csv=$dir_test/results-${IDENTIFIER}.csv
      local vegeta=/usr/local/bin/vegeta
      local dir_out=client-${IDENTIFIER:-0}

      ulimit -n 1048576	# use the same limits as HAProxy pod
#      sysctl -w net.ipv4.tcp_tw_reuse=1	# safe to use on client side

      # Length of a content of an exported environment variable is limited by 128k - <variable length> - 1
      # i.e.: for TARGET_HOST the limit is 131059; if you get "Argument list too long", you know you've hit it 
#      echo $TARGET_HOST | tr ':' '\n' | sed 's|^|GET http://|' > ${targets_lst}

      get_cfg ${RUN}/${IDENTIFIER}/${targets_awk} > ${targets_awk} 
      get_cfg targets | awk -f ${targets_awk} > ${targets_lst} || \
        die $? "${RUN} failed: $?: unable to retrieve vegeta targets list \`${VEGETA_TARGETS}'"
      VEGETA_RPS=$(get_cfg ${RUN}/VEGETA_RPS)
      PBENCH_DIR=$(get_cfg PBENCH_DIR)

      $timeout \
        $vegeta attack -connections ${idle_connections} \
                       -targets=${targets_lst} \
                       -rate=${VEGETA_RPS:-$rate} \
                       -timeout=${requests_timeout} \
                       -duration=${RUN_TIME}s > ${results_bin}
      $(timeout_exit_status) || die $? "${RUN} failed: $?"

      # process the results
      $vegeta report < ${results_bin}
      $vegeta dump -dumper csv -inputs=${results_bin} > ${results_csv}
#      $vegeta report -reporter=plot < ${results_bin} > ${latency_html}	# plotted html files are too large
      graph_total_latency_pctl ${results_csv} $dir_out
      graph_time_bytes_hits_latency ${results_csv} $dir_out

      have_server "${GUN}" && \
        scp -rp $dir_out *.txt *.csv ${GUN}:${PBENCH_DIR}
      $(timeout_exit_status) || die $? "${RUN} failed: scp: $?"

      announce_finish
    ;;

    *)
      die 1 "Need to specify what to run."
    ;;
  esac
  timeout_exit_status
}

main
