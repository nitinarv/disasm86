module Disassembler
    (
          disassemble
        , textrep
        , Instruction(..)
        , Operation(..)
        , Operand(..)
        , Register(..)
        , GPR(..)
        , RegHalf(..)
        , Immediate(..)
    ) where

import Control.Monad (join)
import Data.ByteString.Lazy (ByteString)
import Data.Word (Word8, Word64)
import Data.Int (Int64)
import Data.Binary.Get
import Data.Bits
import Data.List (intercalate)
import Data.Maybe (isJust, isNothing, fromJust)
import Control.Applicative ( (<|>) )

import qualified Data.ByteString.Lazy as B

data Instruction = Instruction {
      inPrefix    :: [Prefix]
    , inOperation :: Operation
    , inOperands  :: [Operand]
    } deriving (Show, Eq)

data Prefix = Prefix
    deriving (Show, Eq)

data Operation =
        I_ADD
      | I_OR
      | I_ADC
      | I_SBB
      | I_AND
      | I_SUB
      | I_XOR
      | I_CMP
    deriving (Show, Eq)

data Operand =
        Op_Mem {
                mSize  :: Int
              , mReg   :: Register
              , mIdx   :: Register
              , mScale :: Word8
              , mDisp  :: ImmediateS
              }
      | Op_Reg Register
    deriving (Show, Eq)

data Register =
        RegNone
      | Reg8 GPR RegHalf
      | Reg16 GPR
      | Reg32 GPR
      | Reg64 GPR
      | RegSeg SReg
    deriving (Show, Eq)

data GPR = RAX | RCX | RDX | RBX | RSP | RBP | RSI | RDI | R8 | R9 | R10 | R11 | R12 | R13 | R14 | R15
    deriving (Show, Eq, Ord, Enum)

data SReg = ES | CS | SS | DS | FS | GS
    deriving (Show, Eq, Ord, Enum)

data RegHalf = HalfL | HalfH
    deriving (Show, Eq, Ord, Enum)

data Immediate t = Immediate {
        iSize :: Int
      , iValue :: t
    } deriving (Show, Eq)

type ImmediateS = Immediate Int64
type ImmediateU = Immediate Word64

textrep :: Instruction -> String
textrep (Instruction p oper operands) =
    let t1 = opertext oper
        t2 = intercalate ", " (map operandtext operands)
      in case t2 of "" -> t1
                    _  -> t1 ++ " " ++ t2

operandtext :: Operand -> String
operandtext (Op_Reg r) = registertext r
operandtext (Op_Mem _ base RegNone _ (Immediate _ 0)) = "[" ++ registertext base ++ "]"



sibtext :: (Register, Word8) -> String
sibtext _ = "<<sib>>" -- TODO

disassemble :: ByteString -> ([Instruction], ByteString)
disassemble s = case runGetOrFail disassemble1 s of
                    Left _          -> ([], s)
                    Right (r, _, i) -> let (i',r') = disassemble r in (i:i', r')

disassemble1 :: Get Instruction
disassemble1 =  disassemble1' pfxNone

data PrefixState = PrefixState {
          pfxRex ::  Maybe Word8
        , pfxO16 :: Bool
        , pfxA32 :: Bool
    }

pfxNone = PrefixState Nothing False False

--

bits s l i = fromIntegral $ (i `shiftR` s) .&. ((1 `shiftL` l) - 1)

bitTest i v = case v of
                Nothing -> False
                Just n  -> n .&. (bit i) /= 0

-- this is the long mode (64-bit) disassembler
disassemble1' :: PrefixState -> Get Instruction
disassemble1' pfx = do
    opcode <- getWord8
    let bitW = (opcode .&. (bit 0))
        bitD = (opcode .&. (bit 1))
        opWidth = o' bitW (fmap (\x -> (x .&. (bit 4)) /= 0) (pfxRex pfx)) (pfxO16 pfx)
            where o' 0 _ _                  = 8
                  o' 1 Nothing      False   = 32
                  o' 1 Nothing      True    = 16
                  o' 1 (Just False) False   = 32
                  o' 1 (Just False) True    = 16
                  o' 1 (Just True)  _       = 64
      in case opcode of
        0x66 -> disassemble1' (pfx { pfxO16 = True })
        0x67 -> disassemble1' (pfx { pfxA32 = True })

        0x40 -> disassemble1' (pfx { pfxRex = Just 0x40 })
        0x41 -> disassemble1' (pfx { pfxRex = Just 0x41 })
        0x42 -> disassemble1' (pfx { pfxRex = Just 0x42 })
        0x43 -> disassemble1' (pfx { pfxRex = Just 0x43 })
        0x44 -> disassemble1' (pfx { pfxRex = Just 0x44 })
        0x45 -> disassemble1' (pfx { pfxRex = Just 0x45 })
        0x46 -> disassemble1' (pfx { pfxRex = Just 0x46 })
        0x47 -> disassemble1' (pfx { pfxRex = Just 0x47 })
        0x48 -> disassemble1' (pfx { pfxRex = Just 0x48 })
        0x49 -> disassemble1' (pfx { pfxRex = Just 0x49 })
        0x4a -> disassemble1' (pfx { pfxRex = Just 0x4a })
        0x4b -> disassemble1' (pfx { pfxRex = Just 0x4b })
        0x4c -> disassemble1' (pfx { pfxRex = Just 0x4c })
        0x4d -> disassemble1' (pfx { pfxRex = Just 0x4d })
        0x4e -> disassemble1' (pfx { pfxRex = Just 0x4e })
        0x4f -> disassemble1' (pfx { pfxRex = Just 0x4f })

        0x00 -> op2 I_ADD pfx opWidth bitD
        0x01 -> op2 I_ADD pfx opWidth bitD
        0x02 -> op2 I_ADD pfx opWidth bitD
        0x03 -> op2 I_ADD pfx opWidth bitD

        0x08 -> op2 I_OR pfx opWidth bitD
        0x09 -> op2 I_OR pfx opWidth bitD
        0x0a -> op2 I_OR pfx opWidth bitD
        0x0b -> op2 I_OR pfx opWidth bitD

        0x10 -> op2 I_ADC pfx opWidth bitD
        0x11 -> op2 I_ADC pfx opWidth bitD
        0x12 -> op2 I_ADC pfx opWidth bitD
        0x13 -> op2 I_ADC pfx opWidth bitD

        0x18 -> op2 I_SBB pfx opWidth bitD
        0x19 -> op2 I_SBB pfx opWidth bitD
        0x1a -> op2 I_SBB pfx opWidth bitD
        0x1b -> op2 I_SBB pfx opWidth bitD

        0x20 -> op2 I_AND pfx opWidth bitD
        0x21 -> op2 I_AND pfx opWidth bitD
        0x22 -> op2 I_AND pfx opWidth bitD
        0x23 -> op2 I_AND pfx opWidth bitD

        0x28 -> op2 I_SUB pfx opWidth bitD
        0x29 -> op2 I_SUB pfx opWidth bitD
        0x2a -> op2 I_SUB pfx opWidth bitD
        0x2b -> op2 I_SUB pfx opWidth bitD

        0x30 -> op2 I_XOR pfx opWidth bitD
        0x31 -> op2 I_XOR pfx opWidth bitD
        0x32 -> op2 I_XOR pfx opWidth bitD
        0x33 -> op2 I_XOR pfx opWidth bitD

        0x38 -> op2 I_CMP pfx opWidth bitD
        0x39 -> op2 I_CMP pfx opWidth bitD
        0x3a -> op2 I_CMP pfx opWidth bitD
        0x3b -> op2 I_CMP pfx opWidth bitD



        _ -> fail ("invalid opcode " ++ show opcode)
  where
    op2 i pfx opWidth direction = do
        modrm <- getWord8
        let b'mod = bits 6 2 modrm
            b'reg = bits 3 3 modrm
            b'rm  = bits 0 3 modrm
            reg = selectreg 2 b'reg opWidth (pfxRex pfx)
            hasSib = (b'mod /= 3 && b'rm == 4)
            dispSize = case (b'mod, b'rm) of
                (0,5) -> Just 32
                (0,6) -> Just 32
                (1,_) -> Just 8
                (2,_) -> Just 32
                _     -> Nothing
            getDisp sz = case sz of
                Just 8 -> (Immediate 8 . fromIntegral) <$> getWord8
                Just 32 -> (Immediate 32 . fromIntegral) <$> getWord32le
                _  -> return $ Immediate 0 0
            parseSib sib = (RegNone, 0) -- FIXME
          in do
            sib <- if hasSib then (parseSib <$> getWord8) else return (RegNone,0)
            disp <- getDisp dispSize <|> (return $ Immediate 0 0)
            rm <- return $ case b'mod of
                    0 -> Op_Mem opWidth (selectreg 0 b'rm 64 (pfxRex pfx)) (fst sib) (snd sib) disp
                    3 -> Op_Reg (selectreg 0 b'rm opWidth (pfxRex pfx))
            let ops = case direction of
                        0 -> [rm, Op_Reg reg]
                        _ -> [Op_Reg reg, rm]
              in return (Instruction [] i ops)

selectreg rexBit reg opWidth rex = let
                rvec' = case () of
                        _ | bitTest rexBit rex ->
                                [R8, R9, R10, R11, R12, R13, R14, R15]
                          | otherwise ->
                                [RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI]
                rvec = case opWidth of
                        8 | isNothing rex ->
                                [Reg8 RAX HalfL, Reg8 RCX HalfL, Reg8 RDX HalfL, Reg8 RDX HalfL,
                                    Reg8 RAX HalfH, Reg8 RCX HalfH, Reg8 RDX HalfH, Reg8 RDX HalfH]
                          | isJust rex -> map (\i -> Reg8 i HalfL) rvec'
                        16 -> map Reg16 rvec'
                        32 -> map Reg32 rvec'
                        64 -> map Reg64 rvec'
            in rvec !! reg

--

opertext :: Operation -> String
opertext I_ADD = "add"
opertext I_OR  = "or"
opertext I_ADC = "adc"
opertext I_SBB = "sbb"
opertext I_AND = "and"
opertext I_SUB = "sub"
opertext I_XOR = "xor"
opertext I_CMP = "cmd"


--

registertext :: Register -> String
registertext (Reg64 RAX) = "rax"
registertext (Reg64 RCX) = "rcx"
registertext (Reg64 RDX) = "rdx"
registertext (Reg64 RBX) = "rbx"
registertext (Reg64 RSP) = "rsp"
registertext (Reg64 RBP) = "rbp"
registertext (Reg64 RSI) = "rsi"
registertext (Reg64 RDI) = "rdi"
registertext (Reg64 R8)  = "r8"
registertext (Reg64 R9)  = "r9"
registertext (Reg64 R10) = "r10"
registertext (Reg64 R11) = "r11"
registertext (Reg64 R12) = "r12"
registertext (Reg64 R13) = "r13"
registertext (Reg64 R14) = "r14"
registertext (Reg64 R15) = "r15"

registertext (Reg32 RAX) = "eax"
registertext (Reg32 RCX) = "ecx"
registertext (Reg32 RDX) = "edx"
registertext (Reg32 RBX) = "ebx"
registertext (Reg32 RSP) = "esp"
registertext (Reg32 RBP) = "ebp"
registertext (Reg32 RSI) = "esi"
registertext (Reg32 RDI) = "edi"
registertext (Reg32 R8)  = "r8d"
registertext (Reg32 R9)  = "r9d"
registertext (Reg32 R10) = "r10d"
registertext (Reg32 R11) = "r11d"
registertext (Reg32 R12) = "r12d"
registertext (Reg32 R13) = "r13d"
registertext (Reg32 R14) = "r14d"
registertext (Reg32 R15) = "r15d"

registertext (Reg16 RAX) = "ax"
registertext (Reg16 RCX) = "cx"
registertext (Reg16 RDX) = "dx"
registertext (Reg16 RBX) = "bx"
registertext (Reg16 RSP) = "sp"
registertext (Reg16 RBP) = "bp"
registertext (Reg16 RSI) = "si"
registertext (Reg16 RDI) = "di"
registertext (Reg16 R8)  = "r8w"
registertext (Reg16 R9)  = "r9w"
registertext (Reg16 R10) = "r10w"
registertext (Reg16 R11) = "r11w"
registertext (Reg16 R12) = "r12w"
registertext (Reg16 R13) = "r13w"
registertext (Reg16 R14) = "r14w"
registertext (Reg16 R15) = "r15w"

registertext (Reg8 RAX HalfL) = "al"
registertext (Reg8 RCX HalfL) = "cl"
registertext (Reg8 RDX HalfL) = "dl"
registertext (Reg8 RBX HalfL) = "bl"
registertext (Reg8 RSP HalfL) = "spl"
registertext (Reg8 RBP HalfL) = "bpl"
registertext (Reg8 RSI HalfL) = "sil"
registertext (Reg8 RDI HalfL) = "dil"
registertext (Reg8 R8 HalfL)  = "r8b"
registertext (Reg8 R9 HalfL)  = "r9b"
registertext (Reg8 R10 HalfL) = "r10b"
registertext (Reg8 R11 HalfL) = "r11b"
registertext (Reg8 R12 HalfL) = "r12b"
registertext (Reg8 R13 HalfL) = "r13b"
registertext (Reg8 R14 HalfL) = "r14b"
registertext (Reg8 R15 HalfL) = "r15b"

registertext (Reg8 RAX HalfH) = "ah"
registertext (Reg8 RCX HalfH) = "ch"
registertext (Reg8 RDX HalfH) = "dh"
registertext (Reg8 RBX HalfH) = "bh"