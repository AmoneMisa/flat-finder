FROM docker.elastic.co/elasticsearch/elasticsearch:9.4.2

COPY analysis-icu-9.4.2.zip /tmp/analysis-icu.zip

RUN bin/elasticsearch-plugin install \
    --batch \
    file:///tmp/analysis-icu.zip \
    && rm /tmp/analysis-icu.zip