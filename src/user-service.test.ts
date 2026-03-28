import { formatUserForDisplay } from "./user-service";

describe("user-service", () => {
    describe("formatUserForDisplay", () => {
        it("should format an admin user correctly", () => {
            const user = {
                id: 1,
                name: "Jane Doe",
                email: "jane@limble.com",
                role: "admin",
                created_at: "2025-01-15T00:00:00Z",
            };

            expect(formatUserForDisplay(user)).toBe("[Admin] Jane Doe <jane@limble.com>");
        });

        it("should format a regular user correctly", () => {
            const user = {
                id: 2,
                name: "John Smith",
                email: "john@limble.com",
                role: "user",
                created_at: "2025-02-20T00:00:00Z",
            };

            expect(formatUserForDisplay(user)).toBe("[User] John Smith <john@limble.com>");
        });

        it("should trim whitespace from names", () => {
            const user = {
                id: 3,
                name: "  Alice  ",
                email: "alice@limble.com",
                role: "user",
                created_at: "2025-03-10T00:00:00Z",
            };

            expect(formatUserForDisplay(user)).toBe("[User] Alice <alice@limble.com>");
        });
    });
});
