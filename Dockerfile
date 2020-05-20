# The Docker tag of Go image to use
ARG GO_VERSION
# The name of Terraform provider
ARG TF_PROVIDER_NAME
# The version of Terraform provider (i.e. tag name)
ARG TF_PROVIDER_VERSION
# Where the required code is within the provider repo
ARG TF_PROVIDER_REPO_DIR

FROM golang:${GO_VERSION} AS generation_base
# Re-introduce args, otherwise they won't be useable
ARG TF_PROVIDER_NAME
ARG TF_PROVIDER_VERSION
ARG TF_PROVIDER_REPO_DIR

# Install git and clone the given provider repository at specified tag
RUN apk update \
  && apk add git \
  && git clone 'https://github.com/terraform-providers/terraform-provider-'"${TF_PROVIDER_NAME}" --branch "${TF_PROVIDER_VERSION}" --depth 1

WORKDIR "$GOPATH/terraform-provider-${TF_PROVIDER_NAME}/${TF_PROVIDER_REPO_DIR}"
COPY "generation/*.go" ./
RUN sed -i 's/^package '"$(basename "${TF_PROVIDER_REPO_DIR}")"'$/package main/' *.go \
  && go build -o api_generator *.go \
  && mkdir -p /outputs/api/resources /outputs/api/schemas /outputs/codegen \
  && ./api_generator resources "${TF_PROVIDER_NAME}" > /outputs/api/resources/index.ts \
  && ./api_generator inputs "${TF_PROVIDER_NAME}" resource > /outputs/api/schemas/inputs.ts \
  && ./api_generator outputs "${TF_PROVIDER_NAME}" resource > /outputs/api/schemas/outputs.ts \
  && ./api_generator inputs "${TF_PROVIDER_NAME}" data > /outputs/api/schemas/inputs-data.ts \
  && ./api_generator outputs "${TF_PROVIDER_NAME}" data > /outputs/api/schemas/outputs-data.ts \
  && ./api_generator codegen "${TF_PROVIDER_NAME}" > /outputs/codegen/index.ts \
  && ./api_generator projectfile '../../../../..' resources > /outputs/api/resources/tsconfig.json \
  && ./api_generator projectfile '../../../../..' resources schema '../resources' '../../../common/platforms/resources' '../../../common/providers/schemas' > /outputs/api/schemas/tsconfig.json \
  && ./api_generator projectfile '../../../..' codegen "../../../api/providers/${TF_PROVIDER_NAME}/schemas" '../../common/providers' > /outputs/codegen/tsconfig.json \
  && rm -rf "$GOPATH"
