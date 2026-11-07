// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Affero General Public License as published by the Free Software Foundation,
// version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
// details.
//
// You should have received a copy of the GNU Affero General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

import { CompileContext } from "@moor/schema/generated/moor-common/compile-context";
import { CompileError } from "@moor/schema/generated/moor-common/compile-error";
import { CompileErrorUnion } from "@moor/schema/generated/moor-common/compile-error-union";
import { DuplicateVariable } from "@moor/schema/generated/moor-common/duplicate-variable";
import { Symbol as MoorSymbol } from "@moor/schema/generated/moor-common/symbol";
import { ClientEvent } from "@moor/schema/generated/moor-rpc/client-event";
import { ClientEventUnion } from "@moor/schema/generated/moor-rpc/client-event-union";
import { ClientSuccess } from "@moor/schema/generated/moor-rpc/client-success";
import { DaemonToClientReply } from "@moor/schema/generated/moor-rpc/daemon-to-client-reply";
import { DaemonToClientReplyUnion } from "@moor/schema/generated/moor-rpc/daemon-to-client-reply-union";
import { Kept } from "@moor/schema/generated/moor-rpc/kept";
import { ReplyResult } from "@moor/schema/generated/moor-rpc/reply-result";
import { ReplyResultUnion } from "@moor/schema/generated/moor-rpc/reply-result-union";
import { TaskCompleted } from "@moor/schema/generated/moor-rpc/task-completed";
import { TaskEnding } from "@moor/schema/generated/moor-rpc/task-ending";
import { TaskOutcome } from "@moor/schema/generated/moor-rpc/task-outcome";
import { TaskOutcomeEvent } from "@moor/schema/generated/moor-rpc/task-outcome-event";
import { VerbCompilationError } from "@moor/schema/generated/moor-rpc/verb-compilation-error";
import { VerbProgramError } from "@moor/schema/generated/moor-rpc/verb-program-error";
import { VerbProgramErrorUnion } from "@moor/schema/generated/moor-rpc/verb-program-error-union";
import { VerbProgramFailure } from "@moor/schema/generated/moor-rpc/verb-program-failure";
import { VerbProgramResponse } from "@moor/schema/generated/moor-rpc/verb-program-response";
import { VerbProgramResponseReply } from "@moor/schema/generated/moor-rpc/verb-program-response-reply";
import { VerbProgramResponseUnion } from "@moor/schema/generated/moor-rpc/verb-program-response-union";
import { Var } from "@moor/schema/generated/moor-var/var";
import { VarInt } from "@moor/schema/generated/moor-var/var-int";
import { VarUnion } from "@moor/schema/generated/moor-var/var-union";
import { Builder } from "flatbuffers";
import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import { test, type TestContext } from "node:test";
import { WebSocketServer } from "ws";
import { evalBody, MoorWebClient } from "../src/moor-service.ts";

const actor = { mooId: "test", playerId: "builder" };
function completed() {
    const b = new Builder();
    const value = Var.createVar(b, VarUnion.VarInt, VarInt.createVarInt(b, 1n));
    const ending = TaskCompleted.createTaskCompleted(b, value);
    const outcome = TaskOutcome.createTaskOutcome(b, Kept.Yes, TaskEnding.TaskCompleted, ending);
    TaskOutcomeEvent.startTaskOutcomeEvent(b);
    TaskOutcomeEvent.addTaskId(b, 1n);
    TaskOutcomeEvent.addOutcome(b, outcome);
    const event = TaskOutcomeEvent.endTaskOutcomeEvent(b);
    b.finish(ClientEvent.createClientEvent(b, ClientEventUnion.TaskOutcomeEvent, event, 0n));
    return b.asUint8Array();
}

/** A DuplicateVariable compile error for `b` at line 2, column 47. */
function duplicateVariableError(b: Builder): number {
    const context = CompileContext.createCompileContext(b, 2n, 47n);
    const name = MoorSymbol.createSymbol(b, b.createString("b"));
    DuplicateVariable.startDuplicateVariable(b);
    DuplicateVariable.addContext(b, context);
    DuplicateVariable.addVarName(b, name);
    const detail = DuplicateVariable.endDuplicateVariable(b);
    return CompileError.createCompileError(b, CompileErrorUnion.DuplicateVariable, detail);
}

/** The web host's answer to an eval of code with that duplicate variable: no task ran. */
const duplicateVariable = JSON.stringify({
    code: "compilation_error",
    error: "Duplicate variable in scope @ 2/47: b",
    compile_error: { DuplicateVariable: [{ line_col: [2, 47] }, "b"] },
});

/** The web host's answer to programming a verb with that duplicate variable. */
function programFailure() {
    const b = new Builder();
    const compilation = VerbCompilationError.createVerbCompilationError(b, duplicateVariableError(b));
    const error = VerbProgramError.createVerbProgramError(b, VerbProgramErrorUnion.VerbCompilationError, compilation);
    const failure = VerbProgramFailure.createVerbProgramFailure(b, error);
    const response = VerbProgramResponse.createVerbProgramResponse(
        b,
        VerbProgramResponseUnion.VerbProgramFailure,
        failure,
    );
    const reply = VerbProgramResponseReply.createVerbProgramResponseReply(b, response);
    const daemonReply = DaemonToClientReply.createDaemonToClientReply(
        b,
        DaemonToClientReplyUnion.VerbProgramResponseReply,
        reply,
    );
    const success = ClientSuccess.createClientSuccess(b, daemonReply);
    b.finish(ReplyResult.createReplyResult(b, ReplyResultUnion.ClientSuccess, success));
    return b.asUint8Array();
}

async function host(t: TestContext, timeoutMs = 1000, password = "test") {
    let logins = 0;
    let writes = 0;
    const commands: string[] = [];
    const evals: string[] = [];
    const passwords: string[] = [];
    const http = createServer((req, res) => {
        const body: Buffer[] = [];
        req.on("data", chunk => body.push(chunk));
        const url = new URL(req.url!, "http://host");
        if (url.pathname === "/auth/connect") {
            req.on("end", () => {
                const password = new URLSearchParams(Buffer.concat(body).toString()).get("password")!;
                passwords.push(password);
                if (password === "stale") return void res.writeHead(401).end("Invalid credentials");
                logins++;
                setTimeout(() => {
                    res.setHeader("X-Moor-Auth-Token", `token-${logins}`);
                    res.end();
                }, 10);
            });
        } else if (url.pathname === "/expired") {
            writes++;
            res.writeHead(401).end("Expired token");
        } else if (url.pathname === "/rejected") {
            res.end(JSON.stringify({ result: { Failure: { error: "Permission denied" } } }));
        } else if (url.pathname === "/v1/eval") {
            evals.push(url.searchParams.get("timeout_ms") ?? "none");
            res.writeHead(422, { "Content-Type": "application/json" });
            res.end(duplicateVariable);
        } else if (url.pathname.startsWith("/v1/verbs/")) {
            res.writeHead(422, { "Content-Type": "application/x-flatbuffers" });
            res.end(programFailure());
        } else if (url.pathname === "/hang") {
            // The client must abort this request.
        } else res.end(JSON.stringify({ ok: true }));
    });
    const ws = new WebSocketServer({ server: http });
    ws.on("connection", socket => {
        socket.on("message", raw => {
            const command = raw.toString();
            commands.push(command);
            if (command === "hang") return;
            if (command === "disconnect") return socket.close();
            setTimeout(() => {
                if (socket.readyState === socket.OPEN) socket.send(completed());
            }, command === "slow" ? 80 : 5);
        });
    });
    http.listen(0, "127.0.0.1");
    await once(http, "listening");
    const address = http.address();
    assert.ok(address && typeof address !== "string");
    const client = new MoorWebClient({
        timeoutMs,
        moos: [{
            id: "test",
            description: "Test",
            connectAddress: `http://127.0.0.1:${address.port}`,
            players: [{ id: "builder", username: "Builder", password }],
        }],
    }, () => ({
        moos: [{
            id: "test",
            description: "Test",
            connectAddress: `http://127.0.0.1:${address.port}`,
            players: [{ id: "builder", username: "Builder", password: "test" }],
        }],
    }));
    t.after(async () => {
        await client.close();
        for (const socket of ws.clients) socket.terminate();
        ws.close();
        http.closeAllConnections();
        await new Promise<void>(resolve => http.close(() => resolve()));
    });
    return { client, commands, evals, passwords, logins: () => logins, writes: () => writes };
}

test("concurrent requests share authentication and expired mutations are never replayed", async t => {
    const h = await host(t);
    await Promise.all([h.client.requestJson(actor, "/read"), h.client.requestJson(actor, "/read")]);
    assert.equal(h.logins(), 1);
    await assert.rejects(h.client.requestJson(actor, "/expired", { method: "POST" }), /401/);
    assert.equal(h.writes(), 1);
    await h.client.requestJson(actor, "/read");
    assert.equal(h.logins(), 2);
    await assert.rejects(h.client.requestJson(actor, "/rejected"), /Permission denied/);
});

test("HTTP requests have a deadline and propagate cancellation", async t => {
    const { client } = await host(t, 100);
    await assert.rejects(client.requestJson(actor, "/hang"), { name: "TimeoutError" });
    const cancellation = new AbortController();
    const pending = client.requestJson(actor, "/hang", undefined, cancellation.signal);
    cancellation.abort();
    await assert.rejects(pending, { name: "AbortError" });
});

test("commands serialize and wait for task completion", async t => {
    const h = await host(t);
    const slow = h.client.command(actor, "slow");
    const next = h.client.command(actor, "next");
    await new Promise(resolve => setTimeout(resolve, 40));
    assert.deepEqual(h.commands, ["slow"]);
    assert.equal((await slow).error, false);
    assert.equal((await next).error, false);
    assert.deepEqual(h.commands, ["slow", "next"]);
});

test("command timeout and disconnect report unknown outcomes and permit a fresh connection", async t => {
    const h = await host(t, 100);
    const timeout = await h.client.command(actor, "hang");
    assert.equal(timeout.error, true);
    assert.match(timeout.lines.join(), /timed out.*unknown/);
    assert.equal((await h.client.command(actor, "next")).error, false);
    const disconnected = await h.client.command(actor, "disconnect");
    assert.equal(disconnected.error, true);
    assert.match(disconnected.lines.join(), /closed.*unknown/);
    assert.equal((await h.client.command(actor, "next")).error, false);
    assert.equal(h.commands.filter(command => command === "hang").length, 1);
});

test("eval failures say what went wrong and where, under a deadline the daemon enforces", async t => {
    const { client, evals } = await host(t);
    await assert.rejects(
        client.evalExpression(actor, "return 1;"),
        { message: "Eval: Compilation failed. Line 2, column 47: Duplicate variable in scope: b" },
    );
    // The daemon cancels before this client's own 1000 ms deadline.
    assert.deepEqual(evals, ["900"]);
});

test("eval code with statements runs as written; a single expression is returned", () => {
    assert.equal(evalBody("player.name"), "return player.name;");
    assert.equal(evalBody("  1 + 2  "), "return 1 + 2;");
    assert.equal(evalBody("return 5"), "return 5;");
    assert.equal(evalBody("x = 1; return x + 1"), "x = 1; return x + 1;");
    assert.equal(evalBody("\nx = 1;\nreturn x;\n"), "\nx = 1;\nreturn x;");
    assert.equal(evalBody("if (1) return 2; endif"), "if (1) return 2; endif");
    assert.equal(evalBody("\"a;b\""), "return \"a;b\";");
    assert.equal(evalBody("\"a\\\";b\""), "return \"a\\\";b\";");
});

test("programming errors are reported with their position", async t => {
    const { client } = await host(t);
    assert.deepEqual(await client.programVerb(actor, "oid:1", "test", "return;"), {
        ok: false,
        message: "Verb not programmed. Compilation error: Line 2, column 47: Duplicate variable in scope: b",
    });
});

test("a refused login rereads the configuration for changed credentials", async t => {
    const { client, passwords } = await host(t, 1000, "stale");
    await client.requestJson(actor, "/read");
    assert.deepEqual(passwords, ["stale", "test"]);
});
