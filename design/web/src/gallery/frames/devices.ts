/** One way of holding a device: its size and the room its chrome takes. */
export interface DeviceConfiguration {
  id: string;
  label: string;
  width: number;
  height: number;
  /** Points reserved by the status bar and the home indicator. */
  safeAreaTop: number;
  safeAreaBottom: number;
  /** Points reserved by the island's edges when the phone is on its side. */
  safeAreaLeft: number;
  safeAreaRight: number;
}

/** A device and the configurations it can be viewed in. */
export interface Device {
  id: string;
  label: string;
  configurations: DeviceConfiguration[];
}

/**
 * The frames are demonstrations, not a layout engine: they show what a screen
 * is meant to do at a given size, which is a design question before it is a
 * framework one. Web sizes join this list as their own device.
 */
export const devices: Device[] = [
  {
    id: "iphone-17",
    label: "iPhone 17",
    configurations: [
      {
        id: "portrait",
        label: "Portrait",
        width: 393,
        height: 852,
        safeAreaTop: 59,
        safeAreaBottom: 34,
        safeAreaLeft: 0,
        safeAreaRight: 0,
      },
      {
        id: "landscape",
        label: "Landscape",
        width: 852,
        height: 393,
        /* On its side the status bar goes, the indicator shrinks, and both
           long edges give way to the island. */
        safeAreaTop: 0,
        safeAreaBottom: 21,
        safeAreaLeft: 59,
        safeAreaRight: 59,
      },
    ],
  },
];
