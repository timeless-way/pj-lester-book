module GM1 where

import Language
import Utils

runProg :: [Char] -> [Char]
runProg = showResults . eval . compile . parse

type GmState 
 = (GmCode,      -- Current instruction stream
 GmStack,        -- Current stack
 GmHeap,         -- Heap of nodes
 GmGlobals,      -- Global addresses in heap
 GmStats)        -- Statistics
type GmCode = [Instruction]

getCode :: GmState -> GmCode
getCode (i, stack, heap, globals, stats) = i
putCode :: GmCode -> GmState -> GmState
putCode i' (i, stack, heap, globals, stats)
   = (i', stack, heap, globals, stats)

data Instruction 
    = Unwind
    | Pushglobal Name
    | Pushint Int
    | Push Int
    | Mkap
    | Slide Int

instance Eq Instruction 
    where
    Unwind          == Unwind               = True
    Pushglobal a    == Pushglobal b         = a == b
    Pushint a       == Pushint b            = a == b
    Push a          == Push b               = a == b
    Mkap            == Mkap                 = True
    Slide a         == Slide b              = a == b
    _               == _                    = False
type GmStack = [Addr]

getStack :: GmState -> GmStack
getStack (i, stack, heap, globals, stats) = stack
putStack :: GmStack -> GmState -> GmState
putStack stack' (i, stack, heap, globals, stats)
   = (i, stack', heap, globals, stats)
type GmHeap = Heap Node
getHeap :: GmState -> GmHeap
getHeap (i, stack, heap, globals, stats) = heap
putHeap :: GmHeap -> GmState -> GmState
putHeap heap' (i, stack, heap, globals, stats)
   = (i, stack, heap', globals, stats)
data Node 
   = NNum Int              -- Numbers
   | NAp Addr Addr         -- Applications
   | NGlobal Int GmCode    -- Globals
type GmGlobals = ASSOC Name Addr
getGlobals :: GmState -> GmGlobals
getGlobals (i, stack, heap, globals, stats) = globals
statInitial  :: GmStats
statIncSteps :: GmStats -> GmStats
statGetSteps :: GmStats -> Int
type GmStats = Int
statInitial    = 0
statIncSteps s = s+1
statGetSteps s = s
getStats :: GmState -> GmStats
getStats (i, stack, heap, globals, stats) = stats
putStats :: GmStats -> GmState -> GmState
putStats stats' (i, stack, heap, globals, stats)
   = (i, stack, heap, globals, stats')
eval :: GmState -> [GmState]
eval state = state: restStates
             where
             restStates | gmFinal state     = []
                        | otherwise         = eval nextState
             nextState  = doAdmin (step state)
doAdmin :: GmState -> GmState
doAdmin s = putStats (statIncSteps (getStats s)) s
gmFinal :: GmState -> Bool
gmFinal s = case (getCode s) of
                   []        -> True
                   otherwise -> False
step :: GmState -> GmState
step state = dispatch i (putCode is state)
             where (i:is) = getCode state
dispatch :: Instruction -> GmState -> GmState
dispatch (Pushglobal f) = pushglobal f
dispatch (Pushint n)    = pushint n
dispatch Mkap           = mkap
dispatch (Push n)       = push n
dispatch (Slide n)      = slide n
dispatch Unwind         = unwind
pushglobal :: Name -> GmState -> GmState
pushglobal f state
      = putStack (a: getStack state) state
      where a = aLookup (getGlobals state) f (error ("Undeclared global " ++ f))
pushint :: Int -> GmState -> GmState
pushint n state
      = putHeap heap' (putStack (a: getStack state) state)
      where (heap', a) = hAlloc (getHeap state) (NNum n)
mkap :: GmState -> GmState
mkap state
      = putHeap heap' (putStack (a:as') state)
      where (heap', a)  = hAlloc (getHeap state) (NAp a1 a2)
            (a1:a2:as') = getStack state
push :: Int -> GmState -> GmState
push n state
   = putStack (a:as) state
   where   as = getStack state
           a  = getArg (hLookup (getHeap state) (as !! (n+1)))
getArg :: Node -> Addr
getArg (NAp a1 a2) = a2
slide :: Int -> GmState -> GmState
slide n state
      = putStack (a: drop n as) state
      where (a:as) = getStack state
unwind :: GmState -> GmState
unwind state
     = newState (hLookup heap a)
     where
             (a:as) = getStack state
             heap   = getHeap state
             newState (NNum n)      = state
             newState (NAp a1 a2)   = putCode [Unwind] (putStack (a1:a:as) state)
             newState (NGlobal n c) 
                    | length as < n        = error "Unwinding with too few arguments"
                    | otherwise    = putCode c state

compile :: CoreProgram -> GmState
compile program
   = (initialCode, [], heap, globals, statInitial)
   where (heap, globals) = buildInitialHeap program

buildInitialHeap :: CoreProgram -> (GmHeap, GmGlobals)
buildInitialHeap program
  = mapAccuml allocateSc hInitial compiled
  where compiled = map compileSc (preludeDefs ++ program) ++
                   compiledPrimitives

type GmCompiledSC = (Name, Int, GmCode)

allocateSc :: GmHeap -> GmCompiledSC -> (GmHeap, (Name, Addr))
allocateSc heap (name, nargs, instns)
      = (heap', (name, addr))
      where (heap', addr) = hAlloc heap (NGlobal nargs instns)

initialCode :: GmCode
initialCode = [Pushglobal "main", Unwind]

compileSc :: CoreScDefn -> GmCompiledSC
compileSc (name, env, body)
      = (name, length env, compileR body (zip2 env [0..]))

compileR :: GmCompiler
compileR e env = compileC e env ++ [Slide (length env + 1), Unwind]

type GmCompiler = CoreExpr -> GmEnvironment -> GmCode
type GmEnvironment = ASSOC Name Int

compileC :: GmCompiler
compileC (EVar v)    env 
 | elem v (aDomain env)          = [Push n]
 | otherwise                     = [Pushglobal v]
 where n = aLookup env v (error "Can't happen")
compileC (ENum n)    env = [Pushint n]
compileC (EAp e1 e2) env = compileC e2 env ++
                           compileC e1 (argOffset 1 env) ++
                           [Mkap]
argOffset :: Int -> GmEnvironment -> GmEnvironment
argOffset n env = [(v, n+m) | (v,m) <- env]

compiledPrimitives :: [GmCompiledSC]
compiledPrimitives = []

showResults :: [GmState] -> [Char]
showResults states
      = iDisplay (iConcat [
      iStr "Supercombinator definitions", iNewline,
      iInterleave iNewline (map (showSC s) (getGlobals s)),
      iNewline, iNewline, iStr "State transitions", iNewline, iNewline,
      iLayn (map showState states),
      iNewline, iNewline,
      showStats (last states)])
      where (s:ss) = states
showSC :: GmState -> (Name, Addr) -> Iseq
showSC s (name, addr)
      = iConcat [ iStr "Code for ", iStr name, iNewline,
            showInstructions code, iNewline, iNewline]
      where (NGlobal arity code) = (hLookup (getHeap s) addr)
showInstructions :: GmCode -> Iseq
showInstructions is
      = iConcat [iStr "  Code:{",
           iIndent (iInterleave iNewline (map showInstruction is)),
           iStr "}", iNewline]
showInstruction :: Instruction -> Iseq
showInstruction Unwind         = iStr  "Unwind"
showInstruction (Pushglobal f) = (iStr "Pushglobal ") `iAppend` (iStr f)
showInstruction (Push n)       = (iStr "Push ")       `iAppend` (iNum n)
showInstruction (Pushint n)    = (iStr "Pushint ")    `iAppend` (iNum n)
showInstruction Mkap           = iStr  "Mkap"
showInstruction (Slide n)      = (iStr "Slide ")      `iAppend` (iNum n)
showState :: GmState -> Iseq
showState s
   = iConcat [showStack s,         iNewline,
   showInstructions (getCode s),   iNewline]
showStack :: GmState -> Iseq
showStack s
      = iConcat [iStr " Stack:[",
           iIndent (iInterleave iNewline
                       (map (showStackItem s) (reverse (getStack s)))),
           iStr "]"]
showStackItem :: GmState -> Addr -> Iseq
showStackItem s a
      = iConcat [iStr (showaddr a), iStr ": ",
           showNode s a (hLookup (getHeap s) a)]
showNode :: GmState -> Addr -> Node -> Iseq
showNode s a (NNum n)      = iNum n
showNode s a (NGlobal n g) = iConcat [iStr "Global ", iStr v]
   where v = head [n | (n,b) <- getGlobals s, a==b]
showNode s a (NAp a1 a2)   = iConcat [iStr "Ap ", iStr (showaddr a1),
                                      iStr " ",   iStr (showaddr a2)]
showStats :: GmState -> Iseq
showStats s
      = iConcat [ iStr "Steps taken = ", iNum (statGetSteps (getStats s))]
rearrange :: Int -> GmHeap -> GmStack -> GmStack
rearrange n heap as
      = take n as' ++ drop n as
      where as' = map (getArg . hLookup heap) (tl as)
compileArgs :: [(Name, CoreExpr)] -> GmEnvironment -> GmEnvironment
compileArgs defs env
    = zip (map first defs) [n-1, n-2 .. 0] ++ argOffset n env
            where n = length defs
boxInteger :: Int -> GmState -> GmState
boxInteger n state
      = putStack (a: getStack state) (putHeap h' state)
      where (h', a) = hAlloc (getHeap state) (NNum n)
unboxInteger :: Addr -> GmState -> Int
unboxInteger a state
      = ub (hLookup (getHeap state) a)
      where   ub (NNum i) = i
              ub n        = error "Unboxing a non-integer"
pop :: Int -> GmState -> GmState
pop n state
 = putStack (drop n (getStack state)) state
