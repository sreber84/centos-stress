FROM centos:latest 

# Install required packages 
RUN yum install -y bc java-1.8.0-openjdk-headless tar && yum clean all

# Setup jmeter
RUN mkdir -p /opt/jmeter && \
    curl -Ls http://mirrors.gigenet.com/apache/jmeter/binaries/apache-jmeter-3.0.tgz \
	| tar xz --strip=1 -C /opt/jmeter && \
        echo "jmeter.save.saveservice.url=true" >> /opt/jmeter/bin/jmeter.properties && \
	ln -s /opt/jmeter/bin/jmeter.sh /usr/bin/jmeter

# Copy entrypoint script
COPY docker-entrypoint.sh test.jmx /

ENTRYPOINT ["/docker-entrypoint.sh"]
