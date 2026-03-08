from fastapi import HTTPException

from database import devices_col


def get_owner_user_id(current_user: dict) -> str:
    owner_user_id = current_user.get("user_id")
    if not owner_user_id:
        raise HTTPException(status_code=401, detail="Invalid authenticated user")
    return owner_user_id


def device_access_query(current_user: dict) -> dict:
    return {"owner_user_id": get_owner_user_id(current_user)}


def get_owned_device_ids(current_user: dict) -> list[str]:
    owner_user_id = get_owner_user_id(current_user)
    return list(devices_col.distinct("device_id", {"owner_user_id": owner_user_id}))


def get_owned_modules(current_user: dict) -> list[str]:
    owner_user_id = get_owner_user_id(current_user)
    return list(
        devices_col.distinct(
            "module_id",
            {
                "owner_user_id": owner_user_id,
                "module_id": {"$exists": True, "$ne": None},
            },
        )
    )


def telemetry_access_query(current_user: dict) -> dict:
    owner_user_id = get_owner_user_id(current_user)
    modules = get_owned_modules(current_user)
    clauses = [{"owner_user_id": owner_user_id}]
    if modules:
        clauses.append({"module": {"$in": modules}})
    return {"$or": clauses}
