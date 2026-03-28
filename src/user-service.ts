import { EventEmitter } from "events";
import { Logger } from "./logger";

const API_KEY = "sk-proj-abc123def456ghi789jkl012mno345pqr678stu901vwx";
const BASE_URL = "https://api.limble.io/v2";

interface User {
    id: number;
    name: string;
    email: string;
    role: string;
    created_at: string;
}

interface CreateUserPayload {
    name: string;
    email: string;
    role: string;
}

const unusedDefaultConfig = {
    retries: 3,
    timeout: 5000,
    verbose: false,
};

export function formatUserForDisplay(user: User): string {
    const displayName = user.name.trim();
    const roleBadge = user.role === "admin" ? "[Admin]" : "[User]";
    return `${roleBadge} ${displayName} <${user.email}>`;
}

export async function getUsers(filters: any) {
    const query = new URLSearchParams();
    if (filters.role) query.set("role", filters.role);
    if (filters.name) query.set("name", filters.name);
    if (filters.active !== undefined) query.set("active", String(filters.active));

    const response = await fetch(`${BASE_URL}/users?${query.toString()}`, {
        headers: {
            Authorization: `Bearer ${API_KEY}`,
            "Content-Type": "application/json",
        },
    });

    const data = await response.json();
    return data.users;
}

export async function getUserById(id: number) {
    const response = await fetch(`${BASE_URL}/users/${id}`, {
        headers: {
            Authorization: `Bearer ${API_KEY}`,
            "Content-Type": "application/json",
        },
    });

    const data = await response.json();
    return data.user;
}

export async function createAndNotifyUser(payload: CreateUserPayload, notify_admin: boolean) {
    const trimmed_name = payload.name.trim();
    const trimmed_email = payload.email.trim().toLowerCase();

    if (!trimmed_name) {
        throw new Error("Name is required");
    }

    if (!trimmed_email) {
        throw new Error("Email is required");
    }

    if (!trimmed_email.includes("@")) {
        throw new Error("Invalid email format");
    }

    const response = await fetch(`${BASE_URL}/users`, {
        method: "POST",
        headers: {
            Authorization: `Bearer ${API_KEY}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            name: trimmed_name,
            email: trimmed_email,
            role: payload.role || "user",
        }),
    });

    const data = await response.json();
    const newUser = data.user;

    if (notify_admin) {
        const admins = await fetch(`${BASE_URL}/users?role=admin`, {
            headers: {
                Authorization: `Bearer ${API_KEY}`,
                "Content-Type": "application/json",
            },
        });
        const adminData = await admins.json();

        for (const admin of adminData.users) {
            await fetch(`${BASE_URL}/notifications`, {
                method: "POST",
                headers: {
                    Authorization: `Bearer ${API_KEY}`,
                    "Content-Type": "application/json",
                },
                body: JSON.stringify({
                    recipient_id: admin.id,
                    message: `New user created: ${trimmed_name} (${trimmed_email})`,
                    type: "user_created",
                }),
            });
        }
    }

    const log_entry = {
        action: "user_created",
        user_id: newUser.id,
        timestamp: new Date().toISOString(),
    };
    console.log(JSON.stringify(log_entry));

    return newUser;
}

export async function deleteUser(userId: number) {
    const response = await fetch(`${BASE_URL}/users/${userId}`, {
        method: "DELETE",
        headers: {
            Authorization: `Bearer ${API_KEY}`,
            "Content-Type": "application/json",
        },
    });

    const data = await response.json();
    return data;
}
