FROM debian:bullseye-slim as builder

# Instalando dependências do projeto OSRM
RUN apt-get update && \
    apt-get -y --no-install-recommends install ca-certificates cmake make git gcc g++ libbz2-dev libxml2-dev wget \
    libzip-dev libboost1.74-all-dev lua5.4 liblua5.4-dev pkg-config -o APT::Install-Suggests=0 -o APT::Install-Recommends=0

# Criando diretório para o repositório OSRM
RUN mkdir -p /srv/osrm
WORKDIR /srv/osrm

# Clonando repositório OSRM
RUN git clone https://github.com/Project-OSRM/osrm-backend.git

RUN NPROC=${BUILD_CONCURRENCY:-$(nproc)} && \
    ldconfig /usr/local/lib && \
    git clone --branch v2021.3.0 --single-branch https://github.com/oneapi-src/oneTBB.git && \
    cd oneTBB && \
    mkdir build && \
    cd build && \
    cmake -DTBB_TEST=OFF -DCMAKE_BUILD_TYPE=Release ..  && \
    cmake --build . && \
    cmake --install .

# Criando diretório para compilação do projeto
RUN mkdir /srv/osrm/osrm-backend/build

# Compilando o projeto OSRM
WORKDIR /srv/osrm/osrm-backend/build
RUN cmake ..
RUN cmake --build .
RUN cmake --build . --target install

# Baixando e processando dados do mapa
WORKDIR /srv/osrm/osrm-backend/

FROM osrm/osrm-backend:latest

RUN wget http://download.geofabrik.de/south-america/brazil/sudeste-latest.osm.pbf

# Executar o processo de extração do mapa
RUN osrm-extract -p /opt/car.lua /srv/osrm/osrm-backend/sudeste-latest.osm.pbf

# Executar o processo de particionamento dos dados
RUN osrm-partition /srv/osrm/osrm-backend/sudeste-latest.osrm

# Executar o processo de personalização dos dados
RUN osrm-customize /srv/osrm/osrm-backend/sudeste-latest.osrm

# Expondo o serviço de roteamento do OSRM
EXPOSE 5000

# Definindo limites de recursos para o contêiner
CMD ["docker", "run", "-t", "-i", "--memory", "0", "--cpus", "0", "-p", "5000:5000", "-v", "${PWD}:/data", "osrm/osrm-backend", "osrm-routed", "--algorithm", "mld", "/data/sudeste-latest.osrm"]
