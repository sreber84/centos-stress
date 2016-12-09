#!/bin/sh

### binaries ####################################################################
pctl_bin=pctl

### functions ###################################################################
graph_d3js() {
  local graph_title="$1"
  local graph_data_html="$2"
  local graph_data_in="$3"
  local dir_out="$4"

  mkdir -p $dir_out

  cat >$dir_out/$graph_data_html<<EOF
<!DOCTYPE HTML>
<html>
  <head>
    <meta charset="utf-8">
    <link href="/static/css/v0.3/jschart.css" rel="stylesheet" type="text/css" media="all">
  </head>
  <body>
    <script src="/static/js/v0.3/d3.min.js"></script>
    <script src="/static/js/v0.3/d3-queue.min.js"></script>
    <script src="/static/js/v0.3/saveSvgAsPng.js"></script>
    <script src="/static/js/v0.3/jschart.js"></script>
    <center><h2>$graph_title</h2></center>
    <div id="chart_1">
      <script>
        create_jschart("lineChart", "timeseries", "chart_1", "$graph_title", null, null, { csvfiles: [ "$graph_data_in" ], threshold: 0 });
      </script>
    </div>
  </body>
</html>
EOF
}

graph_total_latency_pctl() {
  local graph_dir="$1"
  local results="$2"
  local dir_out="$3"
  local graph_conf=$(realpath ${graph_dir}/total_latency_pctl.conf)
  local graph_data_in=$dir_out/total_latency_pctl.txt
  local graph_image_out=$dir_out/total_latency_pctl.png
 
  mkdir -p $dir_out
  rm -f $graph_data_in
  printf "# http_status	90%%	95%%	99%%\n" > $graph_data_in
  for err in $(awk -F, '{print $2}' $results | sort -u)
  do
    printf "%s\t" $err >> $graph_data_in
    awk -F, "{if(\$2 == $err) {print (\$3/1000000)}}" < $results  | \
      $pctl_bin >> $graph_data_in
  done
  
  gnuplot \
    -e "data_in='$graph_data_in'" \
    -e "graph_out='$graph_image_out'" \
    $graph_conf
}

graph_time_bytes_hits_latency() {
  local graph_dir="$1"
  local results="$2"
  local dir_out="$3"
  local graph_data_in=$dir_out/time_bhl.txt

  local graph_bytes_conf=$(realpath ${graph_dir}/time_bytes.conf)
  local graph_image_out_bytes=$dir_out/time_bytes.png

  local graph_hits_conf=$(realpath ${graph_dir}/time_hits.conf)
  local graph_image_out_hits=$dir_out/time_hits.png

  local graph_latency_conf=$(realpath ${graph_dir}/time_latency.conf)
  local graph_image_out_latency=$dir_out/time_latency.png

  mkdir -p $dir_out
  printf "# timestamp_s	bytes_out	bytes_in	hits	latency\n" > $graph_data_in
  cat $results | LC_ALL=C sort -t, -n -k1 | \
  awk '
{
  time=int($1/1000000000)	# get seconds [original value in ns]
  latency += ($3/1000000)	# get miliseconds [original value in ns]
  bytes_out += $4
  bytes_in += $5
  hits += 1
  if(time_prev == 0) {
    time_prev=time		# we just started
  }
  if(time_prev != time) {
    printf "%ld\t%ld\t%ld\t%ld\t%lf\n", time_prev, bytes_out, bytes_in, hits, (latency/hits)
    time_prev=time
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
' >> $graph_data_in

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

graph_total_hits() {
  local graph_dir="$1"
  local results="$2"
  local dir_out="$3"
  local graph_conf=$(realpath ${graph_dir}/total_hits.conf)
  local graph_data_in=$dir_out/total_hits.txt
  local graph_image_out_hits=$dir_out/total_hits.png

  mkdir -p $dir_out
  rm -f $graph_data_in

  printf "# http_status	count\n" > $graph_data_in
  for err in $(awk -F, '{print $2}' $results | sort -n -u)
  do
    printf "%s\t" $err >> $graph_data_in
    awk -F, "
{
  if(\$2 == $err) {i++}
}"'
BEGIN {
  i=0
}
END {
  printf "%d\n", i
}' < $results  >> $graph_data_in
  done

  gnuplot \
    -e "data_in='$graph_data_in'" \
    -e "graph_out='$graph_image_out_hits'" \
    $graph_conf
}

graph_latency_per_endpoint() {
  local graph_dir="$1"
  local results="$2"
  local dir_out="$3"
  local graph_data_in=$dir_out/time_latency_per_endpoint.csv
  local unique_endpoints=unique_endpoints.txt

  mkdir -p $dir_out
  rm -f $graph_data_in
  graph_d3js "Latency [ms]" time_latency_per_endpoint.html ${graph_data_in##*/} $dir_out

  awk -F, '{print $7}' $results | sort -u > $unique_endpoints
  awk -F, '
function print_header(name) {
  printf "timestamp_ms" 
  for (v in a) {
    printf ",%s",v
  }
  printf "\n"
}

function print_stats(time) {
  printf "%d",time
  for (v in a) {
    if(a[v]["hits"]) {
      printf ",%lf",a[v]["latency"]/a[v]["hits"]
    } else {
      printf ",0"
    }
  }
  printf "\n"
}

function clear_stats() {
  for (v in a) {
    a[v]["latency"]=0
    a[v]["hits"]=0
  }
}

function main(name) {
  time=int($1/100000000)		# get seconds [original value in ns]
  a[name]["latency"]+=$3/1000000	# get miliseconds [original value in ns]
  a[name]["hits"]++

  if(time_prev == 0) {
    time_prev=time			# we just started
  }
  if(time_prev != time) {
    print_stats(time)
    time_prev=time
    clear_stats()
  }
}

NR==FNR{ # fill a[] with keys from the first file
  a[$1]["latency"]
  a[$1]["hits"]
  next
}
FNR==1{print_header()}			# just started processing the second file ($results)

main($7)				# processing of the second file

BEGIN {
  time_prev=0
}

END {
}
' $unique_endpoints $results >> $graph_data_in
}

main() {
  local graph_dir="${1:-.}"
  local results_csv="${2:-results_sample.csv}"
  local dir_out="${3:-$(dirname $results_csv)/client-${IDENTIFIER:-0}}"

  mkdir -p $dir_out
  graph_total_latency_pctl $graph_dir $results_csv $dir_out
  graph_time_bytes_hits_latency $graph_dir $results_csv $dir_out
  graph_total_hits $graph_dir $results_csv $dir_out
  graph_latency_per_endpoint $graph_dir $results_csv $dir_out
}

main "$@"
