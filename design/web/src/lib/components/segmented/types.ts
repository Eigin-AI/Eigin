/** One option in a `SegmentedControl`. Mirrors `AppSegment`. */
export interface Segment<Value extends string = string> {
  value: Value;
  label: string;
}
