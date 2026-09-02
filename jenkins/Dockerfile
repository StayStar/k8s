FROM jenkins/jenkins:lts-jdk21

ARG KUBECTL_VERSION=v1.36.0
ARG TARGETARCH=amd64

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl docker.io \
  && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" -o /usr/local/bin/kubectl \
  && chmod +x /usr/local/bin/kubectl \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

USER jenkins

