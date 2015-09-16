#!/bin/bash -e

COMPILE=true

while [[ $# > 0 ]]
do
key="$1"

case $key in
    -c|--compile)
    COMPILE=true
    ;;
    -d|--dynamic)
    DYNAMIC=true
    ;;
    -x|--compress)
    COMPRESS_BINARY=true
    ;;
    --test)
    TEST=true
    ;;
    -t|--tag)
    TAG="$2"
    shift # past argument
    ;;
    *)
            # unknown option
    ;;
esac
shift # past argument or value
done

if [ ! "$(ls -A /src)" ];
then
  echo "Error: Must mount Go source code into /src directory"
  exit 990
fi

# Grab Go package name
pkgName="$(go list -e -f '{{.ImportComment}}' 2>/dev/null || true)"

if [ -z "$pkgName" ];
then
  echo "Error: Must add canonical import path to root package"
  exit 992
fi

# Grab just first path listed in GOPATH
goPath="${GOPATH%%:*}"

# Construct Go package path
pkgPath="$goPath/src/$pkgName"

# Set-up src directory tree in GOPATH
mkdir -p "$(dirname "$pkgPath")"

# Link source dir into GOPATH
ln -sf /src "$pkgPath"

if [ -e "$pkgPath/Godeps/_workspace" ];
then
  # Add local godeps dir to GOPATH
  GOPATH=$pkgPath/Godeps/_workspace:$GOPATH
else
  # Get all package dependencies
  go get -t -d -v ./...
fi

if [ "$TEST" = true ];
then
  go test -v ./...
  exit 0
fi

echo "Building $pkgName"
if [ "$DYNAMIC" = true ];
then
  `go build $pkgName`
else
  # Compile statically linked version of package
  `CGO_ENABLED=${CGO_ENABLED:-0} go build -a --installsuffix cgo --ldflags="${LDFLAGS:--s}" $pkgName`
fi

# Grab the last segment from the package name
name=${pkgName##*/}

if [[ $COMPRESS_BINARY == true ]];
then
  goupx $name
fi

if [ -e "/var/run/docker.sock" ] && [ -e "./Dockerfile" ];
then
  # Default TAG_NAME to package name if not set explicitly
  tagName=${command:-"$name":latest}

  # Build the image from the Dockerfile in the package directory
  docker build -t $tagName .
fi
