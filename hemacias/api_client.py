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

    def register_model(
        self,
        *,
        code: str,
        name: str,
        version: str,
        file_path: str,
        sha256: str | None = None,
        dataset_ref: str | None = None,
        imgsz: int | None = None,
        epochs: int | None = None,
        classes: list[str] | None = None,
        status: str = "VALIDACAO",
        model_type: str = "YOLO_SEG",
        trained_at: str | None = None,
        notes: str | None = None,
    ) -> int:
        data = self._request_json(
            "model_register",
            {
                "code": code,
                "name": name,
                "version": version,
                "file_path": file_path,
                "sha256": sha256,
                "dataset_ref": dataset_ref,
                "imgsz": imgsz,
                "epochs": epochs,
                "classes": classes or [],
                "status": status,
                "model_type": model_type,
                "trained_at": trained_at,
                "notes": notes,
            },
        )
        if not data.get("ok"):
            raise RuntimeError(data.get("error", "Falha ao registrar modelo."))
        return int(data["model_id"])

    def upsert_model_metric(
        self,
        *,
        model_id: int,
        component_code: str | None = None,
        precision: float | None = None,
        recall: float | None = None,
        f1: float | None = None,
        map50: float | None = None,
        map5095: float | None = None,
        mae: float | None = None,
        bias: float | None = None,
        mape: float | None = None,
        sample_count: int | None = None,
        notes: str | None = None,
        metric_origin: str = "MANUAL",
    ) -> None:
        data = self._request_json(
            "model_metric_upsert",
            {
                "model_id": model_id,
                "component_code": component_code,
                "metric_origin": metric_origin,
                "precision": precision,
                "recall": recall,
                "f1": f1,
                "map50": map50,
                "map5095": map5095,
                "mae": mae,
                "bias": bias,
                "mape": mape,
                "sample_count": sample_count,
                "notes": notes,
            },
        )
        if not data.get("ok"):
            raise RuntimeError(data.get("error", "Falha ao registrar métrica."))

    def list_models(self) -> list[dict[str, Any]]:
        data = self._request_json("models_list", {})
        if not data.get("ok"):
            raise RuntimeError(data.get("error", "Falha ao consultar modelos."))
        return list(data.get("models", []))

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
