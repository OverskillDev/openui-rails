# Vendored OpenUI conformance fixtures

`1.0/` is a copy of `spec/fixtures/1.0/` from https://github.com/thesysdev/openui
(MIT, Copyright (c) 2011-2024 Thesys Inc.; see `LICENSE` in this directory).
The runner is `test/conformance/conformance_test.rb`. Refresh with:

    cp -R <openui-checkout>/spec/fixtures/1.0 test/fixtures/openui/1.0

`../golden/chat_library.spec.json` is `docs/generated/chat-library.spec.json`
from the same repository: the spec of the reference React chat library, used to
check signature regeneration against real zod-generated output.
