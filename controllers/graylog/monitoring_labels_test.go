package graylog

import (
	"testing"

	loggingService "github.com/Netcracker/qubership-logging-operator/api/v1"
	util "github.com/Netcracker/qubership-logging-operator/controllers/utils"
)

// TestGraylogServiceCarriesNameLabel guards the label the ServiceMonitor "graylog-service-monitor"
// selects on (charts/qubership-logging-operator/templates/graylog/servicemonitor.yaml).
func TestGraylogServiceCarriesNameLabel(t *testing.T) {
	cr := &loggingService.LoggingService{Spec: loggingService.LoggingServiceSpec{
		Graylog: &loggingService.Graylog{AuthProxy: &loggingService.AuthProxy{}},
	}}

	service, err := graylogService(cr)
	if err != nil {
		t.Fatalf("cannot build the Service: %v", err)
	}

	if got := service.Labels["app.kubernetes.io/name"]; got != util.GraylogComponentName {
		t.Errorf("expected the service label app.kubernetes.io/name=%s, got %q", util.GraylogComponentName, got)
	}
}
