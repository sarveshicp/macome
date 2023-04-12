export const idlFactory = ({ IDL }) => {
    return IDL.Service({
      'get_chunk' : IDL.Func(
          [IDL.Nat32, IDL.Vec(IDL.Nat8)],
          [IDL.Vec(IDL.Nat8)],
          [],
        ),
      'upload_chunk' : IDL.Func([IDL.Nat32, IDL.Vec(IDL.Nat8)], [], []),
    });
};