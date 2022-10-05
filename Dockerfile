FROM --platform=$BUILDPLATFORM debian:bullseye as rootfs-fetch

# needs for build on arm64
ENV LIBGUESTFS_BACKEND_SETTINGS force_tcg
RUN apt-get update && apt-get install -y --no-install-recommends simg2img curl python3-requests unzip libguestfs-tools file linux-image-5.10.0-16-$(dpkg --print-architecture) && apt-get -y clean && rm -rf /var/lib/apt/lists/*

ARG TARGETPLATFORM
ARG BUILDPLATFORM
# https://ci.android.com/builds/branches/aosp-android11-gsi/grid
ARG BUILD_NUMBER=9116014

# you might be want to use these envs when try to fix errors
# ENV LIBGUESTFS_DEBUG 1
# ENV LIBGUESTFS_TRACE 1

RUN curl -o aosp_img.zip $(python3 -c 'import requests,re,json,os;a={"amd64":"x86_64","arm64":"arm64"}[os.getenv("TARGETPLATFORM").split("/")[-1]];b=os.getenv("BUILD_NUMBER");r=requests.get("https://ci.android.com/builds/submitted/"+b+"/aosp_"+a+"-userdebug/latest/aosp_"+a+"-img-"+b+".zip").text;print(json.loads(re.search(r"var JSVariables = ({.+?});", r).group(1))["artifactUrl"])') \
    && unzip aosp_img.zip system.img \
    && rm aosp_img.zip \
    && if file system.img | grep -q "Android sparse image"; then simg2img system.img systemfs.img && rm system.img; else mv system.img systemfs.img; fi \
    && mkdir /android \
    && cd /android \
    && guestfish --ro -a /systemfs.img --mount /dev/sda:/ tar-out / - | tar x \
    && rm /systemfs.img

SHELL ["/bin/bash", "-c"]
RUN cd /android/system/apex \
    && for pkg in *.apex ; \
        do dir="/android/apex/${pkg:0:(-5)}" \
        && echo $dir \
        && mkdir $dir && cd $dir \
        && unzip /android/system/apex/$pkg apex_payload.img \
        && guestfish --ro -a apex_payload.img --mount /dev/sda:/ tar-out / - | tar x \
        && rm apex_payload.img \
    ; done

# FROM debian
# COPY --from=rootfs-fetch /android /android

FROM scratch
COPY --from=rootfs-fetch /android /