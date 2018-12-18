#
# Build screenshot image
#
FROM node:8.14.0-jessie

ENV SCREENSHOT_PATH "/opt/apps/screenshot"



ENV IMAGE_OPTIM_DEPS "advancecomp gifsicle jpegoptim libjpeg-progs optipng pngcrush fontconfig fontconfig-config libfontconfig1 unzip build-essential g++ flex bison gperf ruby perl libsqlite3-dev libfontconfig1-dev libicu-dev libfreetype6 libssl-dev libpng-dev libjpeg-dev"
RUN apt-get update && apt-get install -y ${IMAGE_OPTIM_DEPS}

ENV PNGOUT_PKG "pngout-20130221-linux-static"
RUN wget -q http://static.jonof.id.au/dl/kenutils/${PNGOUT_PKG}.tar.gz -O /tmp/${PNGOUT_PKG}.tar.gz && \
    tar -xzpf /tmp/${PNGOUT_PKG}.tar.gz -C /tmp/ && \
    cp -f /tmp/${PNGOUT_PKG}/x86_64/pngout-static /usr/bin/pngout


# TODO: can't this go into YARN deps?
RUN npm install clean-css-cli@4.1.2 uglify-js@3.0.5

# Install chrome
ENV CHROME_APT_KEY_URL "https://dl-ssl.google.com/linux/linux_signing_key.pub"
RUN echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/chrome.list && curl -s ${CHROME_APT_KEY_URL} | apt-key add - && apt-get update && apt-get install -y google-chrome-stable

# Install yarn
ENV YARN_APT_KEY_URL "https://dl.yarnpkg.com/debian/pubkey.gpg"
RUN echo "deb http://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list && curl -s ${YARN_APT_KEY_URL} | apt-key add - && apt-get update && apt-get install -y yarn

# Create screenshot user, used for starting the service inside container
RUN groupadd screenshot && useradd screenshot -m -g screenshot


# Prepare workdir
RUN mkdir -p ${SCREENSHOT_PATH}
WORKDIR ${SCREENSHOT_PATH}

# Copy screenshot code to container
COPY . ${SCREENSHOT_PATH}/

# Install screenshot service
RUN yarn install

# Install startup scripts and config
COPY kubernetes/docker/scripts/* /usr/bin/
COPY kubernetes/docker/etc/default/screenshot /etc/default/screenshot
RUN chmod +x /usr/bin/*.sh

# Cleanup APT temporary packages
RUN apt-get clean
