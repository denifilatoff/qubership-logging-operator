package fluentbit

import (
	"testing"

	loggingService "github.com/Netcracker/qubership-logging-operator/api/v1"
	util "github.com/Netcracker/qubership-logging-operator/controllers/utils"
)

// TestFluentbitPodsCarryNameLabel guards the label the PodMonitor "fluentbit-all-pods"
// selects on (charts/qubership-logging-operator/templates/fluentbit-daemonset/podmonitor.yaml).
func TestFluentbitPodsCarryNameLabel(t *testing.T) {
	daemonSet, err := fluentbitDaemonSet(newTestLoggingService(&loggingService.Fluentbit{
		ContainerLogging: true,
		ConfigmapReload:  &loggingService.ConfigmapReload{},
	}),
		util.DynamicParameters{ContainerRuntimeType: "containerd"})
	if err != nil {
		t.Fatalf("cannot build the DaemonSet: %v", err)
	}

	if got := daemonSet.Spec.Template.Labels["app.kubernetes.io/name"]; got != util.FluentbitComponentName {
		t.Errorf("expected the pod label app.kubernetes.io/name=%s, got %q", util.FluentbitComponentName, got)
	}
}
