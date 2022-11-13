FROM debian:bullseye-slim as builder
#dependence files
#https://www.thun-techblog.com/index.php/blog/jls_sourcefiles/

#install intel-media-va-driver-non-free
# https://linuxhint.com/enable-non-free-packages-debian-11/
RUN echo "deb http://deb.debian.org/debian bullseye main contrib non-free \
deb-src http://deb.debian.org/debian bullseye main contrib non-free \
deb http://deb.debian.org/debian-security bullseye/updates main contrib non-free \
deb-src http://deb.debian.org/debian-security bullseye/updates main contrib non-free \
deb http://deb.debian.org/debian bullseye-updates main contrib non-free \
deb-src http://deb.debian.org/debian bullseye-updates main contrib non-free" >> /etc/apt/sources.list

RUN apt-get update -y && apt-get upgrade -y && apt-get install -y \
    git \
    build-essential \
    cmake \
    pkg-config \
    ninja-build \
    libmp3lame-dev \
    libopus-dev \
    libvorbis-dev \
    libvpx-dev \
    libx265-dev \
    libx264-dev \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libatomic-ops-dev \
    #qsv->
    libmfx1 \
    libmfx-dev \
    libmfx-tools \
    libva-drm2 \
    libva-x11-2 \
    libva-glx2 \
    libx11-dev \
    libigfxcmrt7 \
    libva-dev \
    libdrm-dev \
    intel-media-va-driver-non-free \
    #<-qsv
    automake \
    libtool \
    autoconf \
    nodejs
RUN apt-get install -y \
    meson \
    libxft-dev \
    npm 

#fdk-aac
FROM builder as fdk-aac
WORKDIR /root
RUN git clone https://github.com/mstorsjo/fdk-aac.git && \
    cd fdk-aac && \
    ./autogen.sh && \
    ./configure && \
    make -j$MAKE_JOB_CNT && \
    make install && \
    /sbin/ldconfig

#l-smash
FROM builder as l-smash
WORKDIR /root
RUN git clone https://github.com/l-smash/l-smash.git && \
    cd l-smash && \
    ./configure --enable-shared && \
    make -j$MAKE_JOB_CNT && \
    make install && \
    ldconfig

#AvisynthPlus
FROM builder as avisynth
WORKDIR /root
RUN git clone https://github.com/AviSynth/AviSynthPlus.git && \
    cd AviSynthPlus && mkdir -p avisynth-build && cd avisynth-build && \
    cmake -DCMAKE_CXX_FLAGS=-latomic ../ -G Ninja && ninja && ninja install

#FFmpeg
FROM builder as ffmpeg
WORKDIR /root
RUN git clone --depth 1  -b release/4.3 https://github.com/FFmpeg/FFmpeg.git
COPY --from=avisynth /usr /usr
COPY --from=fdk-aac /usr /usr
RUN cd FFmpeg && \
    #https://www.willusher.io/general/2020/11/15/hw-accel-encoding-rpi4
    ./configure \
    --extra-ldflags="-latomic" \ 
    --extra-cflags="-I/usr/local/include" \ 
    --extra-ldflags="-L/usr/local/lib" \ 
    --target-os=linux \ 
    --enable-gpl \ 
    --disable-doc \ 
    --disable-debug \ 
    --enable-pic \ 
    --enable-avisynth \ 
    --enable-libx264 \ 
    --enable-libx265 \ 
    --enable-libfdk-aac \ 
    --enable-libfreetype \ 
    --enable-libmp3lame \ 
    --enable-libopus \ 
    --enable-libvorbis \ 
    --enable-libvpx \ 
    --enable-nonfree \ 
    #qsv: libmfx
    --enable-libmfx \ 
    --extra-libs=-ldl \
    --disable-x86asm \
    && make -j$MAKE_JOB_CNT \
    && make install

#l-smash-works && chapter_exe
FROM avisynth as l-smash-works
WORKDIR /root
RUN git clone https://github.com/tobitti0/chapter_exe.git
COPY ./dependence /root
COPY --from=l-smash /usr /usr
RUN cd L-SMASH-Works/AviSynth && \
    CC=gcc CXX=gcc LD=gcc LDFLAGS="-Wl,-Bsymbolic,-L/opt/vc/lib" meson build && cd build && ninja -v && ninja install

FROM avisynth as join_logo_scp
WORKDIR /root
RUN git clone --recursive https://github.com/tobitti0/JoinLogoScpTrialSetLinux.git
COPY --from=l-smash-works /root /root
#join_logo_scp
RUN cd JoinLogoScpTrialSetLinux/modules/logoframe/src && \
    make -j$MAKE_JOB_CNT && \
    cd && cp JoinLogoScpTrialSetLinux/modules/logoframe/src/logoframe JoinLogoScpTrialSetLinux/modules/join_logo_scp_trial/bin/logoframe && \
    cd JoinLogoScpTrialSetLinux/modules/join_logo_scp/src && \
    make -j$MAKE_JOB_CNT && \
    cd && cp JoinLogoScpTrialSetLinux/modules/join_logo_scp/src/join_logo_scp JoinLogoScpTrialSetLinux/modules/join_logo_scp_trial/bin/join_logo_scp && \
    cd /root/chapter_exe/src && \
    make -j$MAKE_JOB_CNT && \
    cd && cp chapter_exe/src/chapter_exe JoinLogoScpTrialSetLinux/modules/join_logo_scp_trial/bin/chapter_exe && \
    cd JoinLogoScpTrialSetLinux/modules/join_logo_scp_trial && \
    npm i

FROM avisynth as delogo
WORKDIR /root
#delogo
RUN git clone https://github.com/tobitti0/delogo-AviSynthPlus-Linux.git && \
    cd delogo-AviSynthPlus-Linux/src && \
    make -j$MAKE_JOB_CNT && make install

FROM node:16-bullseye-slim as cmcut
#日本語対応
RUN apt-get update -y && apt-get upgrade -y && apt-get install -y locales
ENV DEBIAN_FRONTEND noninteractive
RUN echo "ja_JP.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen ja_JP.UTF-8 && \
    dpkg-reconfigure locales && \
    /usr/sbin/update-locale LANG=ja_JP.UTF-8
ENV LC_ALL ja_JP.UTF-8

#各ステージでbuid&installされた成果物をコピー(厳密に理解していないので適当に持ってきている)
COPY --from=builder /var /var
COPY --from=builder /lib /lib
COPY --from=fdk-aac /usr /usr
COPY --from=l-smash /usr /usr
COPY --from=avisynth /usr /usr
COPY --from=ffmpeg /usr /usr
COPY --from=l-smash-works /usr /usr
COPY --from=join_logo_scp /usr /usr
COPY --from=join_logo_scp /root/JoinLogoScpTrialSetLinux/ /root/JoinLogoScpTrialSetLinux/
COPY --from=delogo /usr /usr

WORKDIR /root
RUN cd JoinLogoScpTrialSetLinux/modules/join_logo_scp_trial && \
    npm link
#fix: logoframe Cannot load libavisynth.so
RUN cp -r /usr/local/lib/* /lib/x86_64-linux-gnu/
