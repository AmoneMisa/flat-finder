FROM docker.elastic.co/elasticsearch/elasticsearch:9.4.2

COPY --chown=elasticsearch:root \
    analysis-icu-9.4.2.zip \
    /tmp/analysis-icu.zip

RUN bin/elasticsearch-plugin install \
    --batch \
    file:///tmp/analysis-icu.zip \
    && rm -f /tmp/analysis-icu.zip