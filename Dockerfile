# TODO - all security checking of downloaded binaries has been removed
ARG TARGETARCH
ARG BASE_IMAGE
# Golang Build stage for lookup hiera tool
FROM golang:alpine AS tools-build-hiera
ARG HIERA_VERSION
ENV HIERA_VERSION=${HIERA_VERSION:-0.4.6}
ARG HIERA_SHA
ENV HIERA_SHA=${HIERA_SHA:-04c8819}

RUN apk --no-cache add build-base git mercurial gcc && \
  GO111MODULE=on && \
  mkdir -p /tmp/build && \
  cd /tmp/build && \
  \
  # install hiera lookup
  go mod init local/build && \
  go get -d -v github.com/lyraproj/hiera@v${HIERA_VERSION} && \
  go get -d -v github.com/lyraproj/hiera/config && \
  go get -d -v github.com/lyraproj/hiera/api && \
  go get -d -v github.com/lyraproj/hiera/session && \
  go get -d -v github.com/lyraproj/hiera/hiera && \
  go get -d -v github.com/lyraproj/hiera/cli && \
  export BuildTime="$(date "+%m-%d-%Y_%H_%M_%S_%Z")" && \
  export BuildTag=$HIERA_VERSION && \
  export BuildSHA=$HIERA_SHA && \
  go build -ldflags "-X 'github.com/lyraproj/hiera/cli.BuildTag=$BuildTag' -X 'github.com/lyraproj/hiera/cli.BuildSHA=$BuildSHA' -X 'github.com/lyraproj/hiera/cli.BuildTime=$BuildTime'" -o lookup github.com/lyraproj/hiera/lookup && \
  ./lookup --version

FROM ${BASE_IMAGE} AS tools-build
ARG DUMBINIT_VERSION
ARG GOSU_VERSION
ARG GOSU_KEY
ARG SOPS_VERSION
ARG YQ_VERSION
ARG HCLEDIT_VERSION
ARG HCL2JSON_VERSION
ARG PULUMI_VERSION
ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH:-amd64}
ENV DUMBINIT_VERSION $DUMBINIT_VERSION
ENV GOSU_VERSION $GOSU_VERSION
ENV GOSU_KEY B42F6819007F00F88E364FD4036A9C25BF357DD4
ENV SOPS_VERSION $SOPS_VERSION
ENV YQ_VERSION $YQ_VERSION
ENV HCLEDIT_VERSION $HCLEDIT_VERSION
ENV HCL2JSON_VERSION $HCL2JSON_VERSION
ENV PULUMI_VERSION $PULUMI_VERSION
RUN set -ex; \
  \
  fetchDeps=' \
  build-base \
  ca-certificates \
  curl-dev \
  gnupg \
  openssl \
  python3-dev \
  unzip \
  wget \
  git \
  libc6-compat \
  tzdata \
  '; \
  apk add --no-cache --update $fetchDeps && \
  \
  mkdir -p /tmp/build && \
  cd /tmp/build && \
  \
  # Gosu
  wget -O /tmp/build/gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${TARGETARCH}"; \
  wget -O /tmp/build/gosu.asc "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${TARGETARCH}.asc"; \
  \
  ( gpg --keyserver keys.openpgp.org --receive-keys "$GOSU_KEY" \
  || gpg --keyserver hkp://keyserver.ubuntu.com:80 --receive-keys "$GOSU_KEY" ); \
  gpg --batch --verify gosu.asc gosu; \
  chmod +x gosu; \
  \
  # Dumb-init
  wget -O /tmp/build/dumb-init "https://github.com/Yelp/dumb-init/releases/download/v${DUMBINIT_VERSION}/dumb-init_${DUMBINIT_VERSION}_${TARGETARCH}"; \
  chmod +x dumb-init; \
  \
  # Sops
  wget -O /tmp/build/sops "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${TARGETARCH}"; \
  \
  # # yq
  wget -O /tmp/build/yq https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${TARGETARCH}; \
  \
  # hcledit
  wget -c https://github.com/minamijoyo/hcledit/releases/download/v${HCLEDIT_VERSION}/hcledit_${HCLEDIT_VERSION}_linux_${TARGETARCH}.tar.gz -O - | tar -xz -C /tmp/build/ hcledit; \
  # # json2hcl2 # Only used in gengrunt should remove from helper check.
  # wget -c https://github.com/disaac/json2hcl2/releases/download/v0.1.0/json2hcl2_Linux_x86_64.tar.gz -O - | tar -xz -C /tmp/build json2hcl2; \
  # chmod +x json2hcl2; \
  # hcl2json
  wget -O /tmp/build/hcl2json https://github.com/tmccombs/hcl2json/releases/download/v${HCL2JSON_VERSION}/hcl2json_linux_${TARGETARCH}; \
  \
  # Pulumi
  wget -c https://github.com/pulumi/pulumi/releases/download/v${PULUMI_VERSION}/pulumi-v${PULUMI_VERSION}-linux-${TARGETARCH/amd/x}.tar.gz -O - | tar xz --strip=1 -C /tmp/build ; \
  \
  # k8senv
  mkdir -p /tmp/build/.k8senv/bin && wget -O /tmp/build/.k8senv/bin/k8senv https://github.com/navilg/k8senv/releases/latest/download/k8senv-linux-${TARGETARCH}; \
  chmod -R 755 /tmp/build; \
  # tfenv
  git clone --depth=1 https://github.com/tfutils/tfenv.git ./tfenv && rm -rf ./tfenv/.git; \
  # tgenv
  git clone --depth=1 https://github.com/tgenv/tgenv.git ./tgenv && rm -rf ./tgenv/.git; \
  # pkenv
  git clone --depth=1 https://github.com/iamhsa/pkenv.git ./pkenv && rm -rf ./pkenv/.git;

FROM ${BASE_IMAGE} AS terraform-providers

RUN set -exv \
  && apk add --no-cache --update \
  ca-certificates curl unzip zsh \
  && :

WORKDIR /build
ENV PATH=$PATH:/build/bin

ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH:-amd64}

COPY install-zipped-bin ./bin/
RUN mkdir -pv terraform-providers/linux_${TARGETARCH} terraform-providers/linux_amd64

# @hashicorp releases
RUN set -exv \
  && export uri_template='https://releases.hashicorp.com/${name}/${ver}/${name}_${ver}_${arch}.zip' \
  # terraform providers
  && arch=linux_${TARGETARCH} install-zipped-bin ./terraform-providers/linux_${TARGETARCH} \
  terraform-provider-archive:1.2.2 \
  terraform-provider-aws:4.67.0  \
  terraform-provider-aws:2.70.4  \
  terraform-provider-github:2.3.1 \
  terraform-provider-google:2.7.0 \
  terraform-provider-kubernetes:1.11.1 \
  terraform-provider-newrelic:3.20.2 \
  terraform-provider-null:2.1.2 \
  terraform-provider-template:2.1.2 \
  terraform-provider-cloudamqp:1.26.2 \
  terraform-provider-cloudamqp:1.9.4 \
  terraform-provider-pagerduty:2.15.0 \
  && :
# @lmars releases
RUN set -exv \
  && export uri_template='https://github.com/lmars/${name}/releases/download/${full_ver}/${name}-${ver}-${arch}.zip' \
  # packer plugins
  && arch=linux-amd64 install-zipped-bin ./bin \
  packer-post-processor-vagrant-s3:1.4.0 \
  && :
# @WhistleLabs github releases
RUN set -exv \
  && arch=linux-amd64 export uri_template='https://github.com/WhistleLabs/${name}/releases/download/v${full_ver}/${name}_${ver}_${arch}.zip' \
  # packer plugins
  && install-zipped-bin ./bin \
  packer-provisioner-serverspec:0.1.1-whistle0 \
  # terraform providers
  && install-zipped-bin ./terraform-providers/linux_amd64 \
  terraform-provider-datadog:1.9.0-whistle0-tf012 \
  terraform-provider-logentries:1.0.0-whistle0-tf012 \
  terraform-provider-pagerduty:1.2.1-whistle0-tf012 \
  terraform-provider-rabbitmq:1.0.0-whistle0-tf012 \
  && :
# @jianyuan github releases sentry
RUN set -exv \
  && export uri_template='https://github.com/jianyuan/${name}/releases/download/v${full_ver}/${name}_${ver}_${arch}.zip' \
  # terraform providers
  && arch=linux_${TARGETARCH} install-zipped-bin ./terraform-providers/linux_${TARGETARCH} \
  terraform-provider-sentry:0.7.0 \
  && :


FROM ${BASE_IMAGE} as tools-tfenv
ARG TERRAFORM_VERSION
ENV PATH /usr/local/tfenv/bin:$PATH
ENV TERRAFORM_VERSION $TERRAFORM_VERSION
COPY --link --from=tools-build --chmod=755 /tmp/build/tfenv /usr/local/tfenv

FROM ${BASE_IMAGE} as tools-tgenv
ARG TERRAGRUNT_VERSION
ENV PATH /usr/local/tgenv/bin:$PATH
ENV TERRAGRUNT_VERSION $TERRAGRUNT_VERSION
COPY --link --from=tools-build --chmod=755 /tmp/build/tgenv /usr/local/tgenv

FROM ${BASE_IMAGE} as tools-pkenv
ARG PACKER_VERSION
ENV PATH /usr/local/pkenv/bin:$PATH
ENV PACKER_VERSION $PACKER_VERSION
COPY --link --from=tools-build --chmod=755 /tmp/build/pkenv /usr/local/pkenv

FROM ${BASE_IMAGE} as tools-k8senv
ARG KUBECTL_VERSION
ENV KUBECTL_VERSION $KUBECTL_VERSION
COPY --link --from=tools-build --chmod=755 /tmp/build/.k8senv /usr/local/bin/.k8senv

FROM ${BASE_IMAGE} as tools-dumb-init
ARG DUMBINIT_VERSION
ENV DUMBINIT_VERSION $DUMBINIT_VERSION
COPY --link --from=tools-build --chmod=755 /tmp/build/dumb-init /usr/local/bin/dumb-init

FROM ${BASE_IMAGE} as tools-gosu
ARG GOSU_VERSION
ENV GOSU_VERSION $GOSU_VERSION
COPY --link --from=tools-build --chmod=755 /tmp/build/gosu /usr/local/bin/gosu

FROM ${BASE_IMAGE} as tools-hcl2json
ARG HCL2JSON_VERSION
ENV HCL2JSON_VERSION $HCL2JSON_VERSION
COPY --link --from=tools-build --chmod=755 /tmp/build/hcl2json /usr/local/bin/hcl2json

FROM ${BASE_IMAGE} as tools-hcledit
ARG HCLEDIT_VERSION
ENV HCLEDIT_VERSION $HCLEDIT_VERSION
COPY --link --from=tools-build --chmod=755 /tmp/build/hcledit /usr/local/bin/hcledit

FROM ${BASE_IMAGE} as tools-pulumi
ARG PULUMI_VERSION
ENV PULUMI_VERSION $PULUMI_VERSION
COPY --link --from=tools-build --chmod=755 /tmp/build/pulumi* /usr/local/bin/

FROM ${BASE_IMAGE} as tools-sops
ARG SOPS_VERSION
ENV SOPS_VERSION $SOPS_VERSION
COPY --link --from=tools-build --chmod=755 /tmp/build/sops /usr/local/bin/sops

FROM ${BASE_IMAGE} as tools-yq
ARG YQ_VERSION
ENV YQ_VERSION $YQ_VERSION
COPY --link --from=tools-build --chmod=755 /tmp/build/yq /usr/local/bin/yq

FROM ${BASE_IMAGE} as tools-hiera
ARG HIERA_VERSION
ENV HIERA_VERSION=${HIERA_VERSION:-0.4.6}
COPY --link --from=tools-build-hiera --chmod=755 /tmp/build/lookup /usr/local/bin/lookup

FROM ${BASE_IMAGE} as build-terraform-base
ARG TERRAGRUNT_VERSION
ARG PACKER_VERSION
ARG TERRAFORM_VERSION
COPY --link --from=tools-tfenv /usr/local/tfenv /usr/local/tfenv
COPY --link --from=tools-tgenv /usr/local/tgenv /usr/local/tgenv
COPY --link --from=tools-pkenv /usr/local/pkenv /usr/local/pkenv
ENV PATH /usr/local/tfenv/bin:/usr/local/tgenv/bin:/usr/local/pkenv/bin:$PATH

RUN set -exv; \
  \
  fetchDeps=' \
  ca-certificates \
  curl \
  unzip \
  zsh \
  bash \
  fzf \
  curl-dev \
  jq \
  git \
  gnupg \
  openssh \
  openssl \
  unzip \
  aws-cli \
  '; \
  apk add --no-cache --update $fetchDeps && \
  tfenv install ${TERRAFORM_VERSION} && \
  tgenv install ${TERRAGRUNT_VERSION} && \
  pkenv install ${PACKER_VERSION} && \
  # Use the versions specified by default
  tfenv use ${TERRAFORM_VERSION} && \
  tgenv use ${TERRAGRUNT_VERSION} && \
  pkenv use ${PACKER_VERSION} && \
  tfenv list && \
  tgenv list && \
  pkenv list

FROM ${BASE_IMAGE} as tools-glibc
ARG TERRAGRUNT_VERSION
ARG PACKER_VERSION
ARG TERRAFORM_VERSION
COPY --link --from=build-terraform-base / /
RUN mkdir -p /usr/local/bin && \
  mkdir -p /tmp/build && \
  cd /tmp/build && \
  # Install glibc
  wget -q -O /etc/apk/keys/sgerrand.rsa.pub "https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub" && \
  wget -q "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.35-r1/glibc-2.35-r1.apk" && \
  apk add --no-cache --update glibc-2.35-r1.apk postgresql-client && \
  cd / && \
  rm -rf /tmp/build

FROM ${BASE_IMAGE} as build-terraform-providers
COPY --link --from=tools-glibc / /
COPY --link --from=terraform-providers --chmod=777 /build/terraform-providers/ /usr/local/bin/terraform-providers/
RUN for i in /usr/local/pkenv/versions/[0-9]*; do for b in /usr/local/bin/packer-*;do ln -s "${b}" "${i}"/$(basename "${b}");done; done

FROM ${BASE_IMAGE} as build-terraform-full
COPY --link --from=build-terraform-providers / /
COPY --link --from=tools-gosu /usr/local/bin/gosu /usr/local/bin/gosu
COPY --link --from=tools-dumb-init /usr/local/bin/dumb-init /usr/local/bin/dumb-init
COPY --link --from=tools-hcl2json /usr/local/bin/hcl2json /usr/local/bin/hcl2json
COPY --link --from=tools-hcledit /usr/local/bin/hcledit /usr/local/bin/hcledit
COPY --link --from=tools-sops /usr/local/bin/sops /usr/local/bin/sops
COPY --link --from=tools-yq /usr/local/bin/yq /usr/local/bin/yq
COPY --link --from=tools-hiera /usr/local/bin/lookup /usr/local/bin/lookup
COPY tools/covalence/entrypoint.sh /usr/local/bin/
ARG TERRAGRUNT_VERSION
ARG PACKER_VERSION
ARG TERRAFORM_VERSION
ENV SHELL=bash
ENV PATH /usr/local/tfenv/bin:/usr/local/tgenv/bin:/usr/local/pkenv/bin:$PATH

FROM ${BASE_IMAGE} as build-terraform-slim
COPY --link --from=build-terraform-base / /
COPY --link --from=tools-gosu /usr/local/bin/gosu /usr/local/bin/gosu
COPY --link --from=tools-dumb-init /usr/local/bin/dumb-init /usr/local/bin/dumb-init
COPY --link --from=tools-hcl2json /usr/local/bin/hcl2json /usr/local/bin/hcl2json
COPY --link --from=tools-hcledit /usr/local/bin/hcledit /usr/local/bin/hcledit
COPY --link --from=tools-sops /usr/local/bin/sops /usr/local/bin/sops
COPY --link --from=tools-yq /usr/local/bin/yq /usr/local/bin/yq
COPY --link --from=tools-hiera /usr/local/bin/lookup /usr/local/bin/lookup
COPY tools/covalence/entrypoint.sh /usr/local/bin/
ARG TERRAGRUNT_VERSION
ARG PACKER_VERSION
ARG TERRAFORM_VERSION
ENV SHELL=bash
ENV PATH /usr/local/tfenv/bin:/usr/local/tgenv/bin:/usr/local/pkenv/bin:$PATH

FROM ${BASE_IMAGE} as build-terraform-full-pulumi
COPY --link --from=build-terraform-full / /
COPY --link --from=tools-pulumi /usr/local/bin/pulumi* /usr/local/bin/
COPY --link --from=tools-k8senv /usr/local/bin/.k8senv /usr/local/bin/.k8senv
ARG TERRAGRUNT_VERSION
ARG PACKER_VERSION
ARG TERRAFORM_VERSION
ARG PULUMI_VERSION
ARG KUBECTL_VERSION
ENV SHELL=bash
ENV PATH /usr/local/tfenv/bin:/usr/local/tgenv/bin:/usr/local/pkenv/bin:/usr/local/bin/.k8senv/bin:$PATH

RUN k8senv install kubectl v${KUBECTL_VERSION} && \
  k8senv use kubectl v${KUBECTL_VERSION} && \
  k8senv list kubectl && \
  apk add --no-cache --update docker openrc && \
  rc-update add docker boot
COPY tools/covalence/entrypoint.sh /usr/local/bin/


FROM ${BASE_IMAGE} as build-terraform-slim-pulumi
COPY --link --from=build-terraform-slim / /
COPY --link --from=tools-pulumi /usr/local/bin/pulumi* /usr/local/bin/
COPY --link --from=tools-k8senv /usr/local/bin/.k8senv /usr/local/bin/.k8senv
ARG TERRAGRUNT_VERSION
ARG PACKER_VERSION
ARG TERRAFORM_VERSION
ARG PULUMI_VERSION
ARG KUBECTL_VERSION
ENV SHELL=bash
ENV PATH /usr/local/tfenv/bin:/usr/local/tgenv/bin:/usr/local/pkenv/bin:/usr/local/bin/.k8senv/bin:$PATH

RUN k8senv install kubectl v${KUBECTL_VERSION} && \
  k8senv use kubectl v${KUBECTL_VERSION} && \
  k8senv list kubectl && \
  apk add --no-cache --update docker openrc && \
  rc-update add docker boot

COPY tools/covalence/entrypoint.sh /usr/local/bin/

FROM ${BASE_IMAGE} as build-pulumi
COPY --link --from=tools-pulumi /usr/local/bin/pulumi* /usr/local/bin/
COPY --link --from=tools-k8senv /usr/local/bin/.k8senv /usr/local/bin/.k8senv
ARG TERRAGRUNT_VERSION
ARG PACKER_VERSION
ARG TERRAFORM_VERSION
ARG PULUMI_VERSION
ARG KUBECTL_VERSION
ENV HOME=/root
ENV PATH /usr/local/tfenv/bin:/usr/local/tgenv/bin:/usr/local/pkenv/bin:/usr/local/bin/.k8senv/bin:$PATH

RUN apk add --no-cache --update libc6-compat tzdata && \
  k8senv install kubectl v${KUBECTL_VERSION} && \
  k8senv use kubectl v${KUBECTL_VERSION} && \
  k8senv list kubectl && \
  apk add --no-cache --update docker openrc && \
  rc-update add docker boot
