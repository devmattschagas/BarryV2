library barry_testkit;

class PerfHarnessResult {
  const PerfHarnessResult(this.metric, this.value);
  final String metric;
  final num value;
}
