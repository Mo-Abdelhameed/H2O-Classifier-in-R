FROM rocker/tidyverse:latest

RUN install2.r --error \
    --deps TRUE \
    renv

RUN apt-get -y update && apt-get install -y --no-install-recommends \
    ca-certificates \
    dos2unix \
    default-jre \
    && rm -rf /var/lib/apt/lists/*

COPY src ./opt/src

COPY ./entry_point.sh /opt/
RUN chmod +x /opt/entry_point.sh

COPY ./requirements.txt /opt/

# Install R packages with specific versions from requirements.txt

RUN R -e "devtools::install_version('h2o', version = '3.42.0.2', repos = 'http://cran.rstudio.com/')"
RUN R -e "devtools::install_version('jsonlite', version='1.8.7', repos='https://cloud.r-project.org/')"
RUN R -e "devtools::install_version('fastDummies', version='1.7.3', repos='http://cran.rstudio.com/')"

WORKDIR /opt/src
RUN chown -R 1000:1000 /opt/src

USER 1000

ENTRYPOINT ["/opt/entry_point.sh"]
