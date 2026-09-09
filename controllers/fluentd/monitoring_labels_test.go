package fluentd

import (
	"testing"

	loggingService "github.com/Netcracker/qubership-logging-operator/api/v1"
	util "github.com/Netcracker/qubership-logging-operator/controllers/utils"
)

// TestFluentdPodsCarryNameLabel guards the label the PodMonitor "fluentd-pod-monitor"
// selects on (charts/qubership-logging-operator/templates/fluentd/podmonitor.yaml).
func TestFluentdPodsCarryNameLabel(t *testing.T) {
	cr := &loggingService.LoggingService{Spec: loggingService.LoggingServiceSpec{
		Fluentd: &loggingService.Fluentd{
			ConfigmapReload: &loggingService.ConfigmapReload{},
		},
	}}

	daemonSet, err := fluentdDaemonSet(cr, util.DynamicParameters{ContainerRuntimeType: "containerd"})
	if err != nil {
		t.Fatalf("cannot build the DaemonSet: %v", err)
	}

	if got := daemonSet.Spec.Template.Labels["app.kubernetes.io/name"]; got != util.FluentdComponentName {
		t.Errorf("expected the pod label app.kubernetes.io/name=%s, got %q", util.FluentdComponentName, got)
	}
}
