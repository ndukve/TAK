from pydantic import BaseModel
from datetime import datetime


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ShellElevateRequest(BaseModel):
    password: str


class ShellTicketResponse(BaseModel):
    ticket: str
    expires_at: datetime
