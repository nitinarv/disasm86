module DisassemblerSpec (spec)
where

import Test.Hspec
import Test.QuickCheck hiding ((.&.))

import qualified Disassembler as D
import qualified Data.ByteString.Lazy as B

import Data.Word (Word8, Word64)
import Data.Maybe (catMaybes)
import Data.List (intercalate, (\\), union)
import Data.Bits ((.&.))

import Hdis86

import System.Random

spec :: Spec
spec = do
    describe "basic test" $ do
        it "Empty bytestring" $ D.disassemble 0x1000 B.empty `shouldBe` ([], B.empty)

    describe "basic disassembly" $ do
-- 0x0000: add [rax], al
        it "0000" $ D.disassemble 0x1000 (B.pack [0x00, 0x00]) `shouldBe`
            ([D.Instruction [] D.I_ADD [ D.Op_Mem 8 (D.Reg64 D.RAX) (D.RegNone) 0 (D.Immediate 0 0) Nothing
                                       , D.Op_Reg (D.Reg8 D.RAX D.HalfL)]]
            , B.empty)
    describe "static disassembly tests" $ do
        mapM_
            (\bs -> let t = makeTest' bs
                         in it (show t) $ testdis t `shouldBe` refValue t)
            statictests
    describe "quickcheck tests" $ do
        it "matches reference" $ property $ \t -> testdis t `shouldBe` refValue t

toBS :: String -> [Word8]
toBS []        = []
toBS (f1:f2:r) = (read ("0x" ++ [f1,f2])) : toBS r

allopcodes = let
        opcodes1 = [ [o] | o <- [0x00 .. 0xFF] \\ prefixes ]
        opcodes2 = [ [p, o] | p <- tbPfx, o <- [0x00, 0xff] ]
    in opcodes1 ++ opcodes2

allmodrm :: [ [Word8] ]
allmodrm = let
        hassib modrm = (modrm .&. 0x07 == 4 && modrm .&. 0xC0 /= 0xE0)
        hasdisp modrm = (modrm .&. 0xC7 == 0x5 ||
                         modrm .&. 0xC0 == 0x40 ||
                         modrm .&. 0xC0 == 0x80)
        onemodrm mrm = if hasdisp mrm
                        then [ m ++ d | m <- mrm', d <- [[0x00,0x00,0x00,0x00], [0x7f, 0x7f, 0x7f, 0x7f], [0xff, 0xff, 0xff, 0xff]] ]
                        else mrm'
                where mrm' = if hassib mrm
                                then [ mrm : s : [] | s <- [0x00..0xff] ]
                                else [ mrm : [] ]
    in concatMap onemodrm [0x00..0xff]

(prefixes, allprefix, tbPfx) = let
        prefixes = foldr1 union [ insPfx, adPfx, opPfx, sgPfx, rexPfx, tbPfx ]
        allprefix = [ i ++ a ++ o ++ s ++ r | i <- wrap insPfx,
                                                       a <- wrap adPfx,
                                                       o <- wrap opPfx,
                                                       s <- wrap sgPfx,
                                                       r <- wrap rexPfx ]
        wrap l = [] : map (:[]) l
        tbPfx = [ 0x0f ]
        rexPfx = [ 0x40..0x4f ]
        insPfx = [ 0xf0, 0xf2, 0xf3, 0x9b]
        adPfx = [ 0x67 ]
        opPfx = [ 0x66 ]
        sgPfx = [ 0x26, 0x2e, 0x36, 0x3e, 0x64, 0x65 ]
    in (prefixes, allprefix, tbPfx)

data TPrefix = TPrefix [ Word8 ]
    deriving (Show, Eq)
data TOpcode = TOpcode [ Word8 ]
    deriving (Show, Eq)
data TSuffix = TSuffix [ Word8 ]
    deriving (Show, Eq)
data TPad = TPad ( Word8 )
    deriving (Show, Eq)

data Test = Test {
      bytes     :: B.ByteString
    , descr     :: String
    , refValue  :: String
    }
    deriving (Eq)

instance Show Test where show (Test _ d r) = d ++ " -> " ++ r

instance Arbitrary TPrefix where arbitrary = TPrefix <$> elements (allprefix)
instance Arbitrary TOpcode where arbitrary = TOpcode <$> elements (allopcodes)
instance Arbitrary TSuffix where arbitrary = TSuffix <$> elements (allmodrm)
instance Arbitrary TPad    where arbitrary = TPad <$> elements [0x00..0xff]
instance Arbitrary Test    where arbitrary = makeTest <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

makeTest (TPrefix p) (TOpcode o) (TSuffix r) (TPad pad) = makeTest' (p ++ o ++ r ++ (replicate 15 pad))

makeTest' bs = let
        bytes = B.pack bs
        cfg = Config Intel Mode64 SyntaxIntel (0x1000 :: Word64)
        m = head (disassembleMetadata cfg (B.toStrict bytes))
        descr = mdHex m
        ref'' = mdAssembly m
        ref' = (if (last ref'' == ' ') then init else id) ref''
        last7 = reverse (take 7 (reverse ref'))
        ref = case last7 of "invalid" -> ""
                            _         -> ref'
    in Test bytes descr ref

testdis t = intercalate "\n" (map D.textrep (take 1 (fst (D.disassemble 0x1000 (bytes t)))))

----

statictests = map toBS [
      "0000"
    , "9b"
    , "f067662e4b29743a00"
    , "f0364e5c"
    , "f067264699"
    , "f342aa"
    , "f265118ced00000000"
    , "f2662e4f34f4"
    , "f02643c84c5100"
    , "3e410cac"
    , "f067666548c02cb0ac"
    , "f067663e4da5"
    , "f066364450"
    , "662e4b97"
    , "f2676647e9fcb9"
    , "67663e45882431"
    , "f0664a52"
    , "f36664453de484"
    , "52"
    , "4152"
    , "264152"
    , "67264152"
    , "f267264152"
    , "676636451abc1200000000"
    , "f06644cf"
    , "ef"
    , "45ef"
    , "3e45ef"
    , "673e45ef"
    , "f3673e45ef"
    , "bdbdbdbdbdbd"
    , "c2bdbdbdbdbdbd"
    , "c4c2bdbdbdbdbdbd"
    , "b9c4c2bdbdbdbdbdbd"
    , "4bb9c4c2bdbdbdbdbdbd"
    , "3e4bb9c4c2bdbdbdbdbdbd"
    , "663e4bb9c4c2bdbdbdbdbdbd"
    , "f3663e4bb9c4c2bdbdbdbdbdbd"
    , "c3"
    , "44"
    , "e744"
    , "43e744"
    , "2e43e744"
    , "662e43e744"
    , "f3662e43e744"
    , "e644"
    , "43e644"
    , "2e43e644"
    , "662e43e644"
    , "f3662e43e644"
    , "e544"
    , "43e544"
    , "2e43e544"
    , "662e43e544"
    , "f3662e43e544"
    , "67662646ef"
    , "662646ef"
    , "2646ef"
    , "46ef"
    , "ef"
    , "f267662646ef"
    , "59"
    , "4359"
    , "364359"
    , "f2364359"
    , "405c"
    , "415c"
    , "425c"
    , "435c"
    , "445c"
    , "455c"
    , "465c"
    , "475c"
    , "485c"
    , "495c"
    , "4a5c"
    , "4b5c"
    , "4c5c"
    , "4d5c"
    , "4e5c"
    , "4f5c"
    , "f367663645a0ac870000112233445566"
    , "67663645a0ac870000112233445566"
    , "663645a0ac870000112233445566"
    , "3645a0ac870000112233445566"
    , "45a0ac870000112233445566"
    , "a0ac870000112233445566"
    , "f0654bd074327f"
    , "654bd074327f"
    , "4bd074327f"
    , "d074327f"
    , "c6849400000000e7"
    , "4dc6849400000000e7"
    , "654dc6849400000000e7"
    , "66654dc6849400000000e7"
    , "f366654dc6849400000000e7"
    , "69dc17727272"
    , "4b69dc17727272"
    , "664b69dc17727272"
    , "67664b69dc17727272"
    , "f367664b69dc17727272"
    , "f06448a18ce0ffffffff1d1d"
    , "6448a18ce0ffffffff1d1d"
    , "48a18ce0ffffffff1d1d"
    , "a08ce0ffffffff1d1d"
    , "a18ce0ffffffff1d1d"
    , "a28ce0ffffffff1d1d"
    , "a38ce0ffffffff1d1d"
    , "ce"
    , "4ece"
    , "644ece"
    , "f3644ece"
    ]


