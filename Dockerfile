# vim:set ft=dockerfile:
FROM centos:latest

# Set paths for the json LUA module
ENV LUA_PATH ";;/usr/share/lua/5.1/?.lua"
ENV LUA_CPATH ";;/usr/lib64/lua/5.1/?.so"

# Install required packages
RUN yum install -y bc gcc git gnuplot go java-1.8.0-openjdk lua-devel make \
                   openssh-clients rsync tar unzip && \
    yum localinstall -y https://dl.fedoraproject.org/pub/epel/6/x86_64/stress-1.0.4-4.el6.x86_64.rpm \
                        https://dl.fedoraproject.org/pub/epel/7/x86_64/l/lua-json-1.3.2-2.el7.noarch.rpm \
                        https://dl.fedoraproject.org/pub/epel/7/x86_64/l/lua-lpeg-0.12-1.el7.x86_64.rpm && \
    mkdir -p build && cd build && \
    git clone -b stable https://github.com/jmencak/wrk.git && \
      cd wrk && make && cp ./wrk /usr/local/bin && cd .. && \
    git clone https://github.com/jmencak/perf-tools.git && \
      cd perf-tools/pctl && make && cp pctl /usr/local/bin && \
    cd && rm -rf build && \
    yum remove gcc go lua-devel make -y && \
    yum clean all

# Setup jmeter
RUN mkdir -p /opt/jmeter && \
      curl -Ls https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-3.0.tgz \
	| tar xz --strip=1 -C /opt/jmeter && \
        echo "jmeter.save.saveservice.url=true" >> /opt/jmeter/bin/jmeter.properties && \
        echo "jmeter.save.saveservice.thread_counts=true" >> /opt/jmeter/bin/jmeter.properties && \
	echo "jmeter.save.saveservice.autoflush=true" >> /opt/jmeter/bin/user.properties && \
	ln -s /opt/jmeter/bin/jmeter.sh /usr/bin/jmeter && \
      curl -Ls https://jmeter-plugins.org/downloads/file/JMeterPlugins-Standard-1.4.0.zip -O \
               https://jmeter-plugins.org/downloads/file/JMeterPlugins-Extras-1.4.0.zip -O && \
        unzip -n \*.zip -d /opt/jmeter && rm *.zip

WORKDIR /opt/jmeter
COPY docker-entrypoint.sh requests.awk test.jmx wrk.lua root ./

CMD ["./docker-entrypoint.sh"]
