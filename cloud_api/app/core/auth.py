"""Dependency de autenticacao e autorizacao da Cloud_API (Req 18).

Esta dependency, `require_auth`, substitui a antiga `verify_secret` nos
endpoints protegidos (telemetry POST, jobs POST, reserva, escritas da fila e
supply sync/delete/admin-verify). A autorizacao e concedida quando:

- O header `Authorization: Bearer <Firebase_ID_Token>` traz um token valido
  (verificado pelo firebase-admin), do qual derivamos `email`/`uid`; OU
- O header `x-api-key` bate com `settings.API_SECRET_KEY` (compatibilidade com
  o app Flutter e scripts legados).

Caso contrario, a requisicao recebe 401 sem efeito colateral.

Degradacao segura (Req 18.8): a inicializacao concreta do firebase-admin e
feita no startup (ver `app/main.py`). Aqui consumimos essa inicializacao de
forma tolerante: se o firebase-admin nao estiver disponivel/inicializado (ou
a biblioteca sequer importar), `_verify_firebase_token` retorna `None` e toda
validacao de token falha — apenas a `x-api-key` autoriza. O modulo importa sem
erro mesmo sem credenciais configuradas.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

from fastapi import Header, HTTPException

from app.core.config import settings

logger = logging.getLogger("printdeck.cloud_api")


@dataclass
class Identity:
    """Identidade autorizada de uma requisicao.

    `email`/`uid` sao derivados das claims do Firebase_ID_Token quando a
    autorizacao vem por token; ficam `None` quando a autorizacao vem apenas por
    `x-api-key`. `via` indica a origem: "firebase" ou "api_key".
    """

    email: str | None
    uid: str | None
    via: str  # "firebase" | "api_key"


def _verify_firebase_token(token: str) -> dict | None:
    """Valida um Firebase_ID_Token e retorna suas claims, ou `None`.

    Retorna `None` (nao autoriza por token) em qualquer um destes casos:
    - a biblioteca firebase-admin nao esta disponivel;
    - o firebase-admin nao foi inicializado (credenciais ausentes — Req 18.8);
    - o token esta expirado, malformado ou com assinatura invalida (Req 18.5).

    Nunca levanta excecao: falhas de verificacao viram `None`.
    """
    try:
        import firebase_admin
        from firebase_admin import auth as firebase_auth
    except Exception:  # pragma: no cover - ambiente sem firebase-admin
        # Biblioteca indisponivel: degrada para "sem token valido".
        return None

    # Sem app inicializado, nao ha como verificar o token (degradacao segura).
    if not getattr(firebase_admin, "_apps", None):
        return None

    try:
        return firebase_auth.verify_id_token(token)
    except Exception:
        # Token expirado/malformado/assinatura invalida -> nao autoriza por token.
        return None


def require_auth(
    authorization: str | None = Header(default=None),
    x_api_key: str | None = Header(default=None),
) -> Identity:
    """Autoriza por Firebase_ID_Token OU por `x-api-key`; senao, 401.

    1) Tenta o Firebase_ID_Token do header `Authorization: Bearer ...`
       (Req 18.1, 18.2). Token invalido/expirado/malformado nao autoriza por
       token (segue para o fallback).
    2) Fallback para `x-api-key` valida (Req 18.3), exceto quando a chave esta
       vazia ou "disabled".
    3) Sem token valido e sem `x-api-key` valida -> HTTPException 401, sem
       efeito colateral (Req 18.4, 18.5).
    """
    # 1) tenta Firebase_ID_Token (Req 18.1, 18.2)
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization.split(" ", 1)[1].strip()
        if token:
            claims = _verify_firebase_token(token)  # None se invalido/sem credenciais
            if claims is not None:
                return Identity(
                    email=claims.get("email"),
                    uid=claims.get("uid"),
                    via="firebase",
                )

    # 2) fallback x-api-key (Req 18.3)
    if (
        settings.API_SECRET_KEY
        and settings.API_SECRET_KEY != "disabled"
        and x_api_key == settings.API_SECRET_KEY
    ):
        return Identity(email=None, uid=None, via="api_key")

    # 3) nenhum autoriza (Req 18.4, 18.5)
    raise HTTPException(status_code=401, detail="Nao autorizado")
