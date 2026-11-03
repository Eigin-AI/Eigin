import type { Directory } from "./sources";

/** Legacy origin-local record format; directory permissions remain browser-managed. */
export type Recent = {
  id: string;
  name: string;
  lastOpened: number;
  kind: "dir";
  handle: Directory;
};

async function database(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open("eigin-present", 1);
    request.onupgradeneeded = () => request.result.createObjectStore("decks", { keyPath: "id" });
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

/** Read persisted recents without requesting directory access. */
export async function recents(): Promise<Recent[]> {
  const db = await database();
  try {
    return await new Promise<Recent[]>((resolve, reject) => {
      const request = db.transaction("decks").objectStore("decks").getAll();
      request.onsuccess = () =>
        resolve(
          request.result
            .filter((record: { kind: string }) => record.kind === "dir")
            .sort((a: Recent, b: Recent) => b.lastOpened - a.lastOpened),
        );
      request.onerror = () => reject(request.error);
    });
  } finally {
    db.close();
  }
}

/** Save or remove a recent entry using the legacy database schema. */
export async function saveRecent(record: Recent | string): Promise<void> {
  const db = await database();
  try {
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction("decks", "readwrite");
      const store = tx.objectStore("decks");
      if (typeof record === "string") store.delete(record);
      else store.put({ ...record, lastOpened: Date.now() });
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  } finally {
    db.close();
  }
}
