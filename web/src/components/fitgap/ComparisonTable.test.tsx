import { describe, it, expect } from "vitest";
import { render, screen, within } from "@testing-library/react";
import ComparisonTable from "./ComparisonTable";
import type { SkillComparison } from "@/types";

// Shape produced by api/app/services/fit_gap/engine.rb (build_skill_comparisons).
// It sends `expected_level`, not `required_level`, and `overridden`, not `is_override`.
const apiRows: SkillComparison[] = [
  {
    skill_label: "React / Frontend Development",
    skill_id: "sk-eng-001",
    expected_level: 3,
    candidate_level: 2,
    result: "gap",
    delta: -1,
    confidence: "high",
    overridden: false,
  },
  {
    skill_label: "SQL",
    skill_id: "sk-eng-002",
    expected_level: 3,
    candidate_level: 4,
    result: "exceed",
    delta: 1,
    confidence: "medium",
    overridden: true,
  },
  {
    skill_label: "System Design",
    skill_id: "sk-eng-003",
    expected_level: 4,
    candidate_level: null,
    result: "not_assessed",
    delta: null,
    confidence: null,
    overridden: false,
  },
];

function rowFor(label: string) {
  return screen.getByRole("row", { name: new RegExp(label) });
}

describe("ComparisonTable", () => {
  it("shows the required level that the API sends as expected_level", () => {
    render(<ComparisonTable comparisons={apiRows} />);

    expect(within(rowFor("React")).getAllByRole("cell")[1]).toHaveTextContent("L3");
    expect(within(rowFor("System Design")).getAllByRole("cell")[1]).toHaveTextContent("L4");
  });

  it("marks only rows with a human override", () => {
    render(<ComparisonTable comparisons={apiRows} />);

    expect(within(rowFor("SQL")).getByLabelText("Overridden by assessor")).toBeInTheDocument();
    expect(within(rowFor("React")).queryByLabelText("Overridden by assessor")).not.toBeInTheDocument();
  });

  it("does not present a skill that was never assessed as a gap", () => {
    render(<ComparisonTable comparisons={apiRows} />);

    const row = rowFor("System Design");
    expect(within(row).getByText(/not assessed/i)).toBeInTheDocument();
    expect(within(row).queryByText(/gap/i)).not.toBeInTheDocument();
    // No candidate level to show, and nothing numeric invented for it.
    expect(within(row).getAllByRole("cell")[2]).toHaveTextContent("—");
  });

  it("flags a gap that rests on thin evidence instead of stating it flatly", () => {
    const lowConfidenceGap: SkillComparison[] = [
      { ...apiRows[0], confidence: "low" },
    ];
    render(<ComparisonTable comparisons={lowConfidenceGap} />);

    expect(within(rowFor("React")).getByText(/low confidence/i)).toBeInTheDocument();
  });

  it("only shows the override legend when an override exists", () => {
    const { rerender } = render(<ComparisonTable comparisons={apiRows} />);
    expect(screen.getByText(/human override applied/i)).toBeInTheDocument();

    rerender(<ComparisonTable comparisons={[apiRows[0]]} />);
    expect(screen.queryByText(/human override applied/i)).not.toBeInTheDocument();
  });

  it("renders an empty comparison list without crashing and says so", () => {
    render(<ComparisonTable comparisons={[]} />);

    expect(screen.getByText(/no skills to compare/i)).toBeInTheDocument();
  });

  it("keeps a very long skill label inside the table", () => {
    const long = "Distributed Systems ".repeat(20).trim();
    render(<ComparisonTable comparisons={[{ ...apiRows[0], skill_label: long }]} />);

    const cell = within(screen.getByRole("row", { name: /Distributed Systems/ })).getAllByRole("cell")[0];
    expect(cell.className).toMatch(/break-words/);
  });
});
