from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any
import json
import mimetypes
import urllib.error
import urllib.parse
import urllib.request
import uuid


@dataclass(slots=True)
class HemaciasApiClient:
    base_url: str
    api_key: str
    timeout: float = 30.0

    def _url(self, action: str) -> str:
        return self.base_url.rstrip("/") + "/api.php?action=" + urllib.parse.quote(action)

    def _request_json(self, action: str, payload: dict[str, Any]) -> dict[str, Any]:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(
            self._url(action),
            data=body,
            headers={
                "Content-Type": "application/json; charset=utf-8",
                "X-API-Key": self.api_key,
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"API HTTP {exc.code}: {detail}") from exc

    def get_configuration(self, *, sample_id: int | None = None) -> dict[str, Any]:
        data = self._request_json("config", {"sample_id": sample_id})
        if not data.get("ok"):
            raise RuntimeError(data.get("error", "Falha ao carregar configuração."))
        return data

    def upsert_patient(
        self,
        *,
        name: str,
        external_id: str | None = None,
        birth_date: str | None = None,
        sex: str | None = None,
        document: str | None = None,
        notes: str | None = None,
    ) -> int:
        data = self._request_json(
            "patient_upsert",
            {
                "name": name,
                "external_id": external_id,
                "birth_date": birth_date,
                "sex": sex,
                "document": document,
                "notes": notes,
            },
        )
        if not data.get("ok"):
            raise RuntimeError(data.get("error", "Falha ao registrar paciente."))
        return int(data["patient_id"])

    def create_sample(
        self,
        *,
        patient_id: int,
        sample_code: str,
        collected_at: str | None = None,
        sample_type: str = "sangue",
        notes: str | None = None,
        protocol_id: int | None = None,
        protocol_code: str | None = None,
    ) -> int:
        data = self._request_json(
            "sample_create",
            {
                "patient_id": patient_id,
                "sample_code": sample_code,
                "collected_at": collected_at,
                "sample_type": sample_type,
                "notes": notes,
                "protocol_id": protocol_id,
                "protocol_code": protocol_code,
            },
        )
        if not data.get("ok"):
            raise RuntimeError(data.get("error", "Falha ao registrar amostra."))
        return int(data["sample_id"])

    def create_count(
        self,
        *,
        sample_id: int,
        components: list[dict[str, Any]],
        image_path: str | Path | None = None,
        **metadata: Any,
    ) -> dict[str, Any]:
        payload = {"sample_id": sample_id, "components": components, **metadata}
        boundary = "----Hemacias" + uuid.uuid4().hex
        chunks: list[bytes] = []

        def field(name: str, value: str) -> None:
            chunks.extend([
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
                value.encode("utf-8"),
                b"\r\n",
            ])

        field("payload", json.dumps(payload, ensure_ascii=False))

        if image_path is not None:
            path = Path(image_path)
            mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            chunks.extend([
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="image"; filename="{path.name}"\r\n'.encode(),
                f"Content-Type: {mime}\r\n\r\n".encode(),
                path.read_bytes(),
                b"\r\n",
            ])

        chunks.append(f"--{boundary}--\r\n".encode())
        body = b"".join(chunks)
        req = urllib.request.Request(
            self._url("count_create"),
            data=body,
            headers={
                "Content-Type": f"multipart/form-data; boundary={boundary}",
                "X-API-Key": self.api_key,
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as response:
                data = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"API HTTP {exc.code}: {detail}") from exc

        if not data.get("ok"):
            raise RuntimeError(data.get("error", "Falha ao registrar contagem."))
        return data
