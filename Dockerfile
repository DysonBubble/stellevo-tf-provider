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

# Make a dummy build in order to cache layer with all dependencies
WORKDIR "$GOPATH/terraform-provider-${TF_PROVIDER_NAME}/${TF_PROVIDER_REPO_DIR}"
RUN sed -i 's/^package '"$(basename "${TF_PROVIDER_REPO_DIR}")"'$/package main/' *.go \
  && printf 'package main\nimport (\n  "fmt"\n)\n\nfunc main() {\n  fmt.Println("Test")\n}' > dummy.go \
  && go build -o api_generator *.go \
  && rm dummy.go api_generator

# Start from fresh Go image
FROM golang:${GO_VERSION} AS generation

# Re-introduce args, otherwise they won't be useable
ARG TF_PROVIDER_NAME
ARG TF_PROVIDER_REPO_DIR

# Copy the repository + dependencies
COPY --from=generation_base "$GOPATH" "$GOPATH"

# Copy all the Go code into specified folder within provider repository
COPY "common/generation/*.go" "$GOPATH/terraform-provider-${TF_PROVIDER_NAME}/${TF_PROVIDER_REPO_DIR}/"
WORKDIR "$GOPATH/terraform-provider-${TF_PROVIDER_NAME}/${TF_PROVIDER_REPO_DIR}"
# Build the program to generate the files and run it. Store the generated output as files in /outputs folder (they will be copied out from image later in the pipeline)
RUN go build -o api_generator *.go \
  && mkdir -p /outputs/api/resources /outputs/api/schemas /outputs/codegen \
  && ./api_generator resources "${TF_PROVIDER_NAME}" > /outputs/api/resources/index.ts \
  && ./api_generator inputs "${TF_PROVIDER_NAME}" > /outputs/api/schemas/inputs.ts \
  && ./api_generator outputs "${TF_PROVIDER_NAME}" > /outputs/api/schemas/outputs.ts \
  && ./api_generator codegen "${TF_PROVIDER_NAME}" > /outputs/codegen/index.ts \
  && ./api_generator projectfile '../../../../..' resources > /outputs/api/resources/tsconfig.json \
  && ./api_generator projectfile '../../../../..' resources schema '../resources' '../../../common/platforms/resources' '../../../common/providers/schemas' > /outputs/api/schemas/tsconfig.json \
  && ./api_generator projectfile '../../../..' codegen "../../../api/providers/${TF_PROVIDER_NAME}/schemas" '../../common/providers' > /outputs/codegen/tsconfig.json \
  && rm -rf "$GOPATH"
