
# install dotnet dependencies
wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
sudo apt-get update; \
  sudo apt-get install -y apt-transport-https && \
  sudo apt-get update && \
  sudo apt-get install -y dotnet-sdk-5.0
sudo apt-get update; \
  sudo apt-get install -y apt-transport-https && \
  sudo apt-get update && \
  sudo apt-get install -y aspnetcore-runtime-5.0

# run cart service project
cd microservices-demo && git checkout ci-automation && cd ..
mkdir ~/app && cd ~/app
cp ../microservices-demo/src/cartservice/src/cartservice.csproj .
dotnet restore cartservice.csproj -r linux-musl-x64
cp -r ../microservices-demo/src/cartservice/src/* ./
mkdir ~/cartservice
dotnet publish cartservice.csproj -p:PublishSingleFile=true -r linux-musl-x64 --self-contained true -p:PublishTrimmed=True -p:TrimMode=Link -c release -o ~/cartservice --no-restore
cd ../cartservice
GRPC_HEALTH_PROBE_VERSION=v0.3.6 && sudo wget -qO/bin/grpc_health_probe https://github.com/grpc-ecosystem/grpc-health-probe/releases/download/${GRPC_HEALTH_PROBE_VERSION}/grpc_health_probe-linux-amd64 && sudo chmod +x /bin/grpc_health_probe
export ASPNETCORE_URLS=http://*:7070
cp -r ../microservices-demo/src/cartservice/src/* ./
dotnet run
