package fluentbit_forwarder_aggregator

import (
	"testing"

	loggingService "github.com/Netcracker/qubership-logging-operator/api/v1"
	util "github.com/Netcracker/qubership-logging-operator/controllers/utils"
	corev1 "k8s.io/api/core/v1"
)

// TestHAFluentbitPodsCarryNameLabel guards the labels the PodMonitor "fluentbit-all-pods"
// selects on (charts/qubership-logging-operator/templates/fluentbit-daemonset/podmonitor.yaml).
func TestHAFluentbitPodsCarryNameLabel(t *testing.T) {
	cr := &loggingService.LoggingService{Spec: loggingService.LoggingServiceSpec{
		Fluentbit: &loggingService.Fluentbit{
			ContainerLogging: true,
			ConfigmapReload:  &loggingService.ConfigmapReload{},
			Aggregator: &loggingService.FluentbitAggregator{
				Install:         true,
				ConfigmapReload: &loggingService.ConfigmapReload{},
				Resources:       &corev1.ResourceRequirements{},
			},
		},
	}}

	t.Run("forwarder", func(t *testing.T) {
		ds, err := forwarderDaemonSet(cr, util.DynamicParameters{ContainerRuntimeType: "containerd"})
		if err != nil {
			t.Fatalf("cannot build the forwarder DaemonSet: %v", err)
		}
		if got := ds.Spec.Template.Labels["app.kubernetes.io/name"]; got != util.ForwarderFluentbitComponentName {
			t.Errorf("expected the pod label app.kubernetes.io/name=%s, got %q", util.ForwarderFluentbitComponentName, got)
		}
	})

	t.Run("aggregator", func(t *testing.T) {
		statefulSet, err := aggregatorStatefulSet(cr)
		if err != nil {
			t.Fatalf("cannot build the aggregator StatefulSet: %v", err)
		}
		if got := statefulSet.Spec.Template.Labels["app.kubernetes.io/name"]; got != util.AggregatorFluentbitComponentName {
			t.Errorf("expected the pod label app.kubernetes.io/name=%s, got %q", util.AggregatorFluentbitComponentName, got)
		}
	})
}
