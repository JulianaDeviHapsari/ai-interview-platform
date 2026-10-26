import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, act } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import FitGapReportPage from "./FitGapReportPage";

const { getPortfolio, getFitGap, triggerFitGap } = vi.hoisted(() => ({
  getPortfolio: vi.fn(),
  getFitGap: vi.fn(),
  triggerFitGap: vi.fn(),
}));

vi.mock("@/services/sessions", () => ({ sessionsApi: { getPortfolio } }));
vi.mock("@/services/portfolios", () => ({
  portfoliosApi: {
    getFitGap,
    triggerFitGap,
    regenerateFitGap: vi.fn(),
    exportPortfolio: vi.fn(),
  },
}));

const POLL_MS = 5000;

const report = {
  id: 1,
  portfolio_id: 7,
  vacancy_id: 3,
  skill_comparisons: [
    { skill_label: "SQL", expected_level: 3, candidate_level: 3, result: "match", delta: 0, confidence: "high" },
  ],
  culture_narrative: "Strong collaborative fit.",
  overall_narrative: "Recommend proceeding.",
  generated_at: "2026-10-26T02:00:00Z",
};

function httpError(status: number) {
  return Object.assign(new Error(`HTTP ${status}`), { response: { status } });
}

function renderPage() {
  return render(
    <MemoryRouter initialEntries={["/assessments/1/sessions/2/fitgap/3"]}>
      <Routes>
        <Route path="/assessments/:id/sessions/:sessionId/fitgap/:vacancyId" element={<FitGapReportPage />} />
      </Routes>
    </MemoryRouter>
  );
}

// Let pending promises settle, optionally moving the fake clock forward first.
async function tick(ms = 0) {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(ms);
  });
}

describe("FitGapReportPage", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    getPortfolio.mockResolvedValue({ data: { portfolio: { id: 7, generation_status: "complete", skills: [], overrides: [] } } });
    triggerFitGap.mockResolvedValue({ data: { status: "generating" } });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.clearAllMocks();
  });

  it("asks the API to generate the report once, no matter how long generation takes", async () => {
    getFitGap.mockRejectedValue(httpError(404));
    renderPage();

    await tick();
    await tick(POLL_MS * 6);

    expect(triggerFitGap).toHaveBeenCalledTimes(1);
    // ...while still checking whether the report has appeared.
    expect(getFitGap.mock.calls.length).toBeGreaterThan(2);
  });

  it("shows the report and stops polling once it exists", async () => {
    getFitGap.mockRejectedValueOnce(httpError(404)).mockResolvedValue({ data: { report } });
    renderPage();

    await tick();
    await tick(POLL_MS);
    expect(screen.getByText("Strong collaborative fit.")).toBeInTheDocument();

    const callsWhenReady = getFitGap.mock.calls.length;
    await tick(POLL_MS * 5);
    expect(getFitGap.mock.calls.length).toBe(callsWhenReady);
    expect(triggerFitGap).toHaveBeenCalledTimes(1);
  });

  it("tells the user when the report could not be loaded, instead of generating another one", async () => {
    getFitGap.mockRejectedValue(httpError(500));
    renderPage();

    await tick();

    expect(screen.getByRole("alert")).toHaveTextContent(/could not load/i);
    expect(triggerFitGap).not.toHaveBeenCalled();
  });

  it("tells the user when generation could not be started", async () => {
    getFitGap.mockRejectedValue(httpError(404));
    triggerFitGap.mockRejectedValue(httpError(422));
    renderPage();

    await tick();

    expect(screen.getByRole("alert")).toHaveTextContent(/could not start/i);
  });

  it("stops waiting after a while instead of spinning forever", async () => {
    getFitGap.mockRejectedValue(httpError(404));
    renderPage();

    await tick();
    await tick(POLL_MS * 70);

    expect(screen.getByRole("alert")).toHaveTextContent(/longer than expected/i);
    const callsAtGiveUp = getFitGap.mock.calls.length;
    await tick(POLL_MS * 10);
    expect(getFitGap.mock.calls.length).toBe(callsAtGiveUp);
  });

  it("tells the user when the portfolio itself could not be loaded", async () => {
    getPortfolio.mockRejectedValue(httpError(500));
    renderPage();

    await tick();

    expect(screen.getByRole("alert")).toHaveTextContent(/could not load the portfolio/i);
    expect(getFitGap).not.toHaveBeenCalled();
  });
});
