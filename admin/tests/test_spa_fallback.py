import pytest
from starlette.exceptions import HTTPException

from api.main import SPAStaticFiles


async def test_unknown_route_falls_back_to_index_html(tmp_path):
    (tmp_path / "index.html").write_text("<html>spa shell</html>")
    static = SPAStaticFiles(directory=str(tmp_path), html=True)

    scope = {"method": "GET", "path": "/users", "type": "http", "headers": []}
    res = await static.get_response("users", scope)

    assert res.status_code == 200


async def test_missing_asset_still_404s(tmp_path):
    (tmp_path / "index.html").write_text("<html>spa shell</html>")
    static = SPAStaticFiles(directory=str(tmp_path), html=True)

    scope = {"method": "GET", "path": "/assets/missing.js", "type": "http"}
    with pytest.raises(HTTPException) as exc_info:
        await static.get_response("assets/missing.js", scope)
    assert exc_info.value.status_code == 404
