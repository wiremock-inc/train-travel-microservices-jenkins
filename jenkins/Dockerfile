# Jenkins with the WireMock Cloud plugin, configured by jenkins.yaml, running builds on its built-in node.
# Built and started by jenkins/up.sh, which puts the plugin and the CLI in .build/ first.
FROM jenkins/jenkins:lts-jdk21

# newman runs the Postman collection
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends nodejs npm \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g newman
USER jenkins

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV CASC_JENKINS_CONFIG=/var/jenkins_conf/jenkins.yaml
# A rebuilt image's newer plugins replace those already in the Jenkins home volume
ENV PLUGINS_FORCE_UPGRADE=true

ARG PLUGIN_VERSION
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
COPY .build/wiremock-cloud.hpi /tmp/wiremock-cloud.hpi
# jenkins-plugin-cli also installs the plugins the WireMock plugin depends on
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt \
    --plugins "wiremock-cloud:${PLUGIN_VERSION}:file:///tmp/wiremock-cloud.hpi"

COPY .build/wiremock /opt/wiremock-cli/wiremock
COPY jenkins.yaml /var/jenkins_conf/jenkins.yaml
