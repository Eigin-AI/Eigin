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
  /** What the hardware around the screen looks like. Phones unless stated. */
  shape?: "phone" | "watch";
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
  {
    id: "iphone-se",
    label: "iPhone SE",
    configurations: [
      {
        id: "portrait",
        label: "Portrait",
        width: 375,
        height: 667,
        /* No island and no home indicator. */
        safeAreaTop: 20,
        safeAreaBottom: 0,
        safeAreaLeft: 0,
        safeAreaRight: 0,
      },
      {
        id: "landscape",
        label: "Landscape",
        width: 667,
        height: 375,
        safeAreaTop: 0,
        safeAreaBottom: 0,
        safeAreaLeft: 0,
        safeAreaRight: 0,
      },
    ],
  },
  {
    id: "iphone-17-pro-max",
    label: "iPhone 17 Pro Max",
    configurations: [
      {
        id: "portrait",
        label: "Portrait",
        width: 440,
        height: 956,
        safeAreaTop: 62,
        safeAreaBottom: 34,
        safeAreaLeft: 0,
        safeAreaRight: 0,
      },
      {
        id: "landscape",
        label: "Landscape",
        width: 956,
        height: 440,
        safeAreaTop: 0,
        safeAreaBottom: 21,
        safeAreaLeft: 62,
        safeAreaRight: 62,
      },
    ],
  },
  {
    id: "apple-watch",
    label: "Apple Watch",
    configurations: [
      {
        id: "44mm",
        label: "44mm",
        width: 184,
        height: 224,
        /* The time sits in the top inset; watchOS keeps content clear of it. */
        safeAreaTop: 20,
        safeAreaBottom: 8,
        safeAreaLeft: 0,
        safeAreaRight: 0,
        shape: "watch",
      },
      {
        id: "40mm",
        label: "40mm",
        width: 162,
        height: 197,
        safeAreaTop: 19,
        safeAreaBottom: 8,
        safeAreaLeft: 0,
        safeAreaRight: 0,
        shape: "watch",
      },
    ],
  },
];
