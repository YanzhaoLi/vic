// Copyright 2017-2018 VMware, Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package handlers

import (
	"github.com/go-openapi/runtime/middleware"

	"github.com/vmware/vic/lib/apiservers/service/restapi/operations"
)

const (
	welcomeMessage = "You have successfully accessed the VCH Management API."
)

// HelloGet is a handler that returns a static message for interfaces to use during self-signed certificate acceptance workflows
type HelloGet struct {
}

// Handle is the handler implementation that returns a static message for interfaces to use during self-signed certificate acceptance workflows
func (h *HelloGet) Handle(params operations.GetHelloParams) middleware.Responder {
	return operations.NewGetVersionOK().WithPayload(welcomeMessage)
}
