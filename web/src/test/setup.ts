import "@testing-library/jest-dom/vitest";
import { afterEach } from "vitest";
import { cleanup } from "@testing-library/react";

// Vitest runs without globals, so Testing Library cannot register its own
// cleanup hook. Unmount rendered trees between tests to keep them isolated.
afterEach(() => {
  cleanup();
});
