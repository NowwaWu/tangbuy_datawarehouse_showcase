from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from tangbuy_agent.gates import review_sql
from tangbuy_agent.models import Requirement, Stage
from tangbuy_agent.pipeline import DataAgentPipeline


class PipelineTest(unittest.TestCase):
    def test_release_candidate_passes_all_gates(self):
        requirement = Requirement(
            title="Daily paid amount",
            metric="paid_amount",
            dimensions=("shop_id", "country_code"),
            grain="order_line",
            date_field="paid_at",
        )
        result = DataAgentPipeline(ROOT / "examples/metadata/catalog.json").run(requirement)
        self.assertEqual(Stage.RELEASE_CANDIDATE, result.stage)
        self.assertTrue(result.releasable)

    def test_select_star_is_rejected(self):
        results = review_sql(
            "INSERT OVERWRITE TABLE dws_demo_1d PARTITION(ds='\${bizdate}') "
            "SELECT * FROM dwd_demo_di WHERE ds='\${bizdate}'"
        )
        explicit_columns = next(item for item in results if item.name == "explicit-columns")
        self.assertFalse(explicit_columns.passed)


if __name__ == "__main__":
    unittest.main()
