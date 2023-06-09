import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Error "mo:base/Error";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Order "mo:base/Order";
import Result "mo:base/Result";
import SHA256 "SHA256";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Trie "mo:base/Trie";
import Principal "mo:base/Principal";
import Prim "mo:⛔";

import State "State";
import AssetStorage "./AssetStorage";

actor Assets {
    private stable var owner : Principal = Principal.fromText("q45vb-lcydd-emkdj-wgdhi-czsod-imrcm-bv3ze-mkxm6-sd2ox-y5zou-tqe");
    private let BATCH_EXPIRY_NANOS = 300_000_000_000;

    stable var stableAuthorized : [Principal] = [owner];
    stable var stableAssets : [(AssetStorage.Key, State.StableAsset)] = [];

    public func setOwner(o : Text) : async () {
        var b : Buffer.Buffer<Principal> = Buffer.Buffer<Principal>(0);
        for (a in state.authorized.vals()) {
            if (a == Principal.fromText(o)) return;
            b.add(a);
        };
        b.add(Principal.fromText(o));
        state.authorized := Buffer.toArray(b);
    };

    system func preupgrade() {
        stableAuthorized := state.authorized;
        let size = Trie.size(state.assets);
        let assets = Array.init<(AssetStorage.Key, State.StableAsset)>(
            size,
            (
                "",
                {
                    content_type = "";
                    encodings = [];
                },
            ),
        );

        var i = 0;
        for ((k, a) in Trie.iter(state.assets)) {
            assets[i] := (
                k,
                {
                    content_type = a.content_type;
                    encodings = Iter.toArray(Trie.iter(a.encodings));
                },
            );
            i += 1;
        };
        stableAssets := Array.freeze(assets);
    };

    system func postupgrade() {
        stableAuthorized := [];
        stableAssets := [];
    };

    var state = State.State(stableAuthorized, stableAssets);
    state.authorized := [owner];

    private func keyT(x : Text) : Trie.Key<Text> {
        return { hash = Text.hash(x); key = x };
    };
    private func key(x : Nat32) : Trie.Key<Nat32> {
        return { hash = x; key = x };
    };

    public query func cycleBalance() : async Nat {
        Cycles.balance();
    };

    public shared ({ caller }) func authorize(p : Principal) : async () {
        switch (state.isAuthorized(caller)) {
            case (#err(e)) throw Error.reject(e);
            case (#ok()) {
                var b : Buffer.Buffer<Principal> = Buffer.Buffer<Principal>(0);
                for (a in state.authorized.vals()) {
                    if (a == p) return;
                    b.add(a);
                };
                b.add(p);
                state.authorized := Buffer.toArray(b);
            };
        };
    };

    public shared ({ caller }) func clear(
        a : AssetStorage.ClearArguments
    ) : async () {
        switch (state.isAuthorized(caller)) {
            case (#err(e)) throw Error.reject(e);
            case (#ok()) {
                _clear();
            };
        };
    };

    private func _clear() {
        state := State.State(state.authorized, []);
    };

    // public shared ({ caller }) func commit_batch(
    //     a : AssetStorage.CommitBatchArguments,
    // ) : async () {
    //     switch (state.isAuthorized(caller)) {
    //         case (#err(e)) throw Error.reject(e);
    //         case (#ok()) {
    //             let batch_id = a.batch_id;
    //             for (operation in a.operations.vals()) {
    //                 switch (operation) {
    //                     case (#Clear(_)) _clear();
    //                     case (#CreateAsset(a)) {
    //                         switch (_create_asset(a)) {
    //                             case (#err(e)) throw Error.reject(e);
    //                             case (#ok()) {};
    //                         };
    //                     };
    //                     case (#DeleteAsset(a)) {
    //                     };
    //                     case (#SetAssetContent(a)) {
    //                         switch (_set_asset_content(a)) {
    //                             case (#err(e)) throw Error.reject(e);
    //                             case (#ok()) {};
    //                         };
    //                     };
    //                     case (#UnsetAssetContent(a)) {
    //                     };
    //                 };
    //             };
    //         };
    //     };
    // };

    private func _create_asset(
        a : AssetStorage.CreateAssetArguments
    ) : Result.Result<(), Text> {
        switch (Trie.find(state.assets, keyT(a.key), Text.equal)) {
            case (null) {
                let e : Trie.Trie<Text, State.AssetEncoding> = Trie.empty();
                state.assets := Trie.put(
                    state.assets,
                    keyT(a.key),
                    Text.equal,
                    {
                        content_type = a.content_type;
                        encodings = e;
                    },
                ).0;
            };
            case (?asset) {
                if (asset.content_type != a.content_type) {
                    return #err("content type mismatch");
                };
            };
        };
        #ok();
    };

    public shared ({ caller }) func create_batch() : async {
        batch_id : AssetStorage.BatchId;
    } {
        switch (state.isAuthorized(caller)) {
            case (#err(e)) throw Error.reject(e);
            case (#ok()) {
                let batch_id = state.batchID();
                let now = Time.now();
                state.batches := Trie.put(
                    state.batches,
                    key(batch_id),
                    Nat32.equal,
                    {
                        expires_at = now + BATCH_EXPIRY_NANOS;
                    },
                ).0;

                for ((k, b) in Trie.iter(state.batches)) {
                    if (now > b.expires_at) state.batches := Trie.remove(state.batches, key(k), Nat32.equal).0;
                };
                for ((k, c) in Trie.iter(state.chunks)) {
                    switch (Trie.find(state.chunks, key(c.batch_id), Nat32.equal)) {
                        case (null) {
                            state.chunks := Trie.remove(state.chunks, key(k), Nat32.equal).0;
                        };
                        case (?batch) {};
                    };
                };
                { batch_id };
            };
        };
    };

    public shared ({ caller }) func create_chunk({
        content : [Nat8];
        batch_id : AssetStorage.BatchId;
    }) : async {
        chunk_id : AssetStorage.ChunkId;
    } {
        switch (state.isAuthorized(caller)) {
            case (#err(e)) throw Error.reject(e);
            case (#ok()) {
                switch (Trie.find(state.batches, key(batch_id), Nat32.equal)) {
                    case (null) throw Error.reject("batch not found: " # Nat32.toText(batch_id));
                    case (?batch) {
                        state.batches := Trie.put(
                            state.batches,
                            key(batch_id),
                            Nat32.equal,
                            {
                                expires_at = Time.now() + BATCH_EXPIRY_NANOS;
                            },
                        ).0;
                        let chunk_id = state.chunkID();
                        state.chunks := Trie.put(
                            state.chunks,
                            key(chunk_id),
                            Nat32.equal,
                            {
                                batch_id;
                                content;
                            },
                        ).0;
                        { chunk_id };
                    };
                };
            };
        };
    };

    public shared query func get({
        key : AssetStorage.Key;
        accept_encodings : [Text];
    }) : async {
        content : [Nat8];
        sha256 : ?[Nat8];
        content_type : Text;
        content_encoding : Text;
        total_length : Nat;
    } {
        switch (Trie.find(state.assets, keyT(key), Text.equal)) {
            case (null) throw Error.reject("asset not found: " # key);
            case (?asset) {
                for (e in accept_encodings.vals()) {
                    switch (Trie.find(asset.encodings, keyT(e), Text.equal)) {
                        case (null) {};
                        case (?encoding) {
                            return {
                                content = encoding.content_chunks[0];
                                sha256 = ?encoding.sha256;
                                content_type = asset.content_type;
                                content_encoding = e;
                                total_length = encoding.total_length;
                            };
                        };
                    };
                };
            };
        };
        throw Error.reject("no matching encoding found: " # debug_show (accept_encodings));
    };

    public shared query ({ caller }) func get_chunk({
        index : Nat32;
        batch : AssetStorage.BatchId;
    }) : async Result.Result<State.Chunk, Text> {
        switch (Trie.find(state.chunks, key(index), Nat32.equal)) {
            case (?c) {
                return #ok(c);
            };
            case (null) return #err("chunk not found.");
        };
    };

    public shared query ({ caller }) func http_request(
        r : AssetStorage.HttpRequest
    ) : async AssetStorage.HttpResponse {
        let encodings = Buffer.Buffer<Text>(r.headers.size());
        for ((k, v) in r.headers.vals()) {
            if (textToLower(k) == "accept-encoding") {
                for (v in Text.split(v, #text(","))) {
                    encodings.add(v);
                };
            };
        };

        encodings.add("identity"); //for normal asset files

        switch (Trie.find(state.assets, keyT(r.url), Text.equal)) {
            case (null) {};
            case (?asset) {
                for (encoding_name in encodings.vals()) {
                    switch (Trie.find(asset.encodings, keyT(encoding_name), Text.equal)) {
                        case (null) {};
                        case (?encoding) {
                            let headers = [
                                ("Content-Type", asset.content_type),
                                ("Content-Encoding", encoding_name),
                            ];
                            return {
                                body = encoding.content_chunks[0];
                                headers;
                                status_code = 200;
                                streaming_strategy = _create_strategy(
                                    r.url,
                                    0,
                                    asset,
                                    encoding_name,
                                    encoding,
                                );
                            };
                        };
                    };
                };
            };
        };
        {
            body = Blob.toArray(Text.encodeUtf8("asset not found: " # r.url));
            headers = [];
            streaming_strategy = null;
            status_code = 404;
        };
    };

    private func _create_strategy(
        key : Text,
        index : Nat,
        asset : State.Asset,
        encoding_name : Text,
        encoding : State.AssetEncoding,
    ) : ?AssetStorage.StreamingStrategy {
        switch (_create_token(key, index, asset, encoding_name, encoding)) {
            case (null) { null };
            case (?token) {
                ?#Callback({
                    token;
                    callback = http_request_streaming_callback;
                });
            };
        };
    };

    private func textToLower(t : Text) : Text {
        Text.map(t, Prim.charToLower);
    };

    public shared query ({ caller }) func http_request_streaming_callback(
        st : AssetStorage.StreamingCallbackToken
    ) : async AssetStorage.StreamingCallbackHttpResponse {
        switch (Trie.find(state.assets, keyT(st.key), Text.equal)) {
            case (null) throw Error.reject("key not found: " # st.key);
            case (?asset) {
                switch (Trie.find(asset.encodings, keyT(st.content_encoding), Text.equal)) {
                    case (null) throw Error.reject("encoding not found: " # st.content_encoding);
                    case (?encoding) {
                        if (st.sha256 != ?encoding.sha256) {
                            throw Error.reject("SHA-256 mismatch");
                        };
                        {
                            token = _create_token(
                                st.key,
                                st.index,
                                asset,
                                st.content_encoding,
                                encoding,
                            );
                            body = encoding.content_chunks[st.index];
                        };
                    };
                };
            };
        };
    };

    private func _create_token(
        key : Text,
        chunk_index : Nat,
        asset : State.Asset,
        content_encoding : Text,
        encoding : State.AssetEncoding,
    ) : ?AssetStorage.StreamingCallbackToken {
        if (chunk_index + 1 >= encoding.content_chunks.size()) {
            null;
        } else {
            ?{
                key;
                content_encoding;
                index = chunk_index + 1;
                sha256 = ?encoding.sha256;
            };
        };
    };

    public shared query ({ caller }) func list({}) : async [AssetStorage.AssetDetails] {
        let details = Buffer.Buffer<AssetStorage.AssetDetails>(Trie.size(state.assets));
        for ((key, a) in Trie.iter(state.assets)) {
            let encodingsBuffer = Buffer.Buffer<AssetStorage.AssetEncodingDetails>(Trie.size(a.encodings));
            for ((n, e) in Trie.iter(a.encodings)) {
                encodingsBuffer.add({
                    content_encoding = n;
                    sha256 = ?e.sha256;
                    length = e.total_length;
                    modified = e.modified;
                });
            };
            let encodings = Array.sort(
                Buffer.toArray(encodingsBuffer),
                func(
                    a : AssetStorage.AssetEncodingDetails,
                    b : AssetStorage.AssetEncodingDetails,
                ) : Order.Order {
                    Text.compare(a.content_encoding, b.content_encoding);
                },
            );
            details.add({
                key;
                content_type = a.content_type;
                encodings;
            });
        };
        Buffer.toArray(details);
    };

    public shared query ({ caller }) func retrieve(
        p : AssetStorage.Path
    ) : async AssetStorage.Contents {
        switch (Trie.find(state.assets, keyT(p), Text.equal)) {
            case (null) throw Error.reject("asset not found: " # p);
            case (?asset) {
                switch (Trie.find(asset.encodings, keyT("identity"), Text.equal)) {
                    case (null) throw Error.reject("no identity encoding");
                    case (?encoding) {
                        if (encoding.content_chunks.size() > 1) {
                            throw Error.reject("asset too large. use get() or get_chunk() instead");
                        };
                        encoding.content_chunks[0];
                    };
                };
            };
        };
    };

    public query func getAsset(key : Text) : async (Result.Result<State.Asset, Text>) {
        switch (Trie.find(state.assets, keyT(key), Text.equal)) {
            case (null) #err("asset not found: " # key);
            case (?a) return #ok(a);
        };
    };
    public query func getEncoding(n : Text) : async (Result.Result<State.AssetEncoding, Text>) {
        switch (Trie.find(state.assets, keyT(n), Text.equal)) {
            case (null) { #err("asset not found") };
            case (?asset) {
                switch (Trie.find(asset.encodings, keyT("identity"), Text.equal)) {
                    case (null) { #err("encoding not found") };
                    case (?encoding) {
                        return #ok(encoding);
                    };
                };
            };
        };
    };

    private func _set_asset_content(
        a : AssetStorage.SetAssetContentArguments
    ) : Result.Result<(), Text> {
        if (a.chunk_ids.size() == 0) return #err("must have at least one chunk");
        switch (Trie.find(state.assets, keyT(a.key), Text.equal)) {
            case (null) #err("asset not found: " # a.key);
            case (?asset) {
                var content_chunks : Buffer.Buffer<[Nat8]> = Buffer.Buffer<[Nat8]>(0);
                for (chunkID in a.chunk_ids.vals()) {
                    switch (Trie.find(state.chunks, key(chunkID), Nat32.equal)) {
                        case (null) return #err("chunk not found: " # Nat32.toText(chunkID));
                        case (?chunk) {
                            content_chunks.add(chunk.content);
                        };
                    };
                };
                for (chunkID in a.chunk_ids.vals()) {
                    state.chunks := Trie.remove(state.chunks, key(chunkID), Nat32.equal).0;
                };
                var sha256 : [Nat8] = [];
                var total_length = 0;
                for (chunk in content_chunks.vals()) total_length += chunk.size();

                var encodings = asset.encodings;
                encodings := Trie.put(
                    encodings,
                    keyT(a.content_encoding),
                    Text.equal,
                    {
                        modified = Time.now();
                        content_chunks = Buffer.toArray(content_chunks);
                        certified = false;
                        total_length;
                        sha256;
                    },
                ).0;
                state.assets := Trie.put(
                    state.assets,
                    keyT(a.key),
                    Text.equal,
                    {
                        content_type = asset.content_type;
                        encodings;
                    },
                ).0;
                #ok();
            };
        };
    };

    //utility functions
    //
    public func commit_asset_upload(batchId : AssetStorage.BatchId, _key : AssetStorage.Key, _type : Text, chunkIds : [AssetStorage.ChunkId], _content_encoding : Text) : async (Result.Result<(), Text>) {
        var res : Result.Result<(), Text> = _create_asset({
            key = _key;
            content_type = _type;
        });
        switch (res) {
            case (#err _) {
                return #err("check _create_asset");
            };
            case (#ok) {
                var res1 : Result.Result<(), Text> = _set_asset_content({
                    key = _key;
                    sha256 = null;
                    chunk_ids = chunkIds;
                    content_encoding = _content_encoding;
                });
                switch (res1) {
                    case (#err _) {
                        return #err("check _set_asset_content");
                    };
                    case (#ok) {
                        return #ok();
                    };
                };
            };
        };
    };

};
