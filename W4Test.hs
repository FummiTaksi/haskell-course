module W4Test where

import W4
import Impl.Test

import Control.Monad
import Data.List
import Data.IORef
import System.IO
import System.Directory

import Test.QuickCheck hiding (Result,reason,(===))
import Test.QuickCheck.Monadic

main = testExsArgs tests stdArgs {maxSize = 40, maxSuccess = 40}

tests = [[ex1_hello]
        ,[ex2_greet]
        ,[ex3_greet2]
        ,[ex4_getSum]
        ,[ex5_readWords]
        ,[ex6_readUntil]
        ,[ex7_isums]
        ,[ex8_whenM_True, ex8_whenM_False]
        ,[ex9_while]
        ,[ex10_debug]
        ,[ex11_mapM_]
        ,[ex12_forM]
        ,[ex13_doubleCall]
        ,[ex14_compose]
        ,[ex15_mkCounter]
        ,[ex16_hFetchLines]
        ,[ex17_readCSV]
        ,[ex18_compareFiles]
        ,[ex19_interact_terminates, ex19_interact_loop]
        ]

-- -- -- -- --

ex1_hello = monadicIO $ do
  (text,()) <- runc' hello
  stop $ text === "HELLO\nWORLD\n"

word = listOf1 (choose ('a','z'))

ex2_greet = monadicIO $ do
  name <- pick word
  (text,()) <- runc' $ greet name
  stop $ text === ("HELLO "++name++"\n")

ex3_greet2 = monadicIO $ do
  name <- pick word
  (text,()) <- runc (name++"\n") greet2
  stop $ text === ("HELLO "++name++"\n")

ex4_getSum = monadicIO $ do
  a <- pick (arbitrary :: Gen Int)
  b <- pick (arbitrary :: Gen Int)
  (_,ret) <- runc (show a++"\n"++show b++"\n") getSum
  stop $ ret === a+b

ex5_readWords = monadicIO $ do
  words <- pick $ listOf1 word
  (_,ret) <- runc (unlines words) (readWords (length words - 1))
  stop $ ret === sort (init words)

ex6_readUntil = monadicIO $ do
  end <- pick word
  words <- pick $ listOf1 (word `suchThat` (/=end))
  let input = unlines $ words ++ [end]
  (_,ret) <- runc input (readUntil (==end))
  stop . counterexample ("readUntil (==" ++ show end ++ ")\nInput: "++show input) $
    ret === words

ex7_isums = monadicIO $ do
  numbers <- pick . listOf1 $ choose (-10,10)
  let n = length numbers
  (text,ret) <- runc (unlines $ map show numbers) $ isums n
  stop . counterexample ("isums "++show n) $
    conjoin [counterexample "returning" $
             ret === sum numbers,
             counterexample "printing" $
             text === unlines (map show $ scanl1 (+) numbers)]

ex8_whenM_True = monadicIO $ do
  r <- run $ newIORef False
  let op = writeIORef r True
  let cond = return True
  run $ whenM cond op
  v <- run $ readIORef r
  stop $ counterexample "whenM (return True)" $
    v

ex8_whenM_False = monadicIO $ do
  r <- run $ newIORef False
  let op = writeIORef r True
  let cond = return False
  run $ whenM cond op
  v <- run $ readIORef r
  stop $ counterexample "whenM (return False)" $
    not v

ex9_while = monadicIO $ do
  i <- pick $ choose (0,10 :: Int)
  a <- run $ newIORef 0
  b <- run $ newIORef 0
  let ehto = modifyIORef a (+1) >> fmap (<=i) (readIORef a)
      op = modifyIORef b (+1)
  run $ while ehto op
  af <- run $ readIORef a
  bf <- run $ readIORef b
  stop $ counterexample "while" $
    conjoin [counterexample "number of calls to condition" $ af === i+1,
             counterexample "number of calls to operation" $ bf === i]

ex10_debug = monadicIO $ do
  token <- pick word
  value <- pick word
  print <- pick word
  (text,ret) <- runc' $ debug token (putStrLn print >> return value)
  stop $ counterexample ("debug "++show token++" (do putStrLn "++show print++"; return "++show value++")") $
    conjoin [counterexample "tulostus" $ text === (token ++ "\n" ++ print ++ "\n" ++ token ++ "\n"),
             counterexample "palautus" $ ret === value]

ex11_mapM_ = monadicIO $ do
  r <- run $ (newIORef [] :: IO (IORef [Int]))
  lis <- pick $ listOf1 arbitrary
  let op x = modifyIORef r (x:)
  run $ mymapM_ op lis
  ret <- run $ readIORef r
  stop $ counterexample ("mapM op "++show lis) $
    ret === reverse lis

ex12_forM = monadicIO $ do
  r <- run $ (newIORef [] :: IO (IORef [Int]))
  lis <- pick $ listOf1 arbitrary
  let op x = do modifyIORef r (x:)
                return $ x+1
  ret <- run $ myforM lis op
  out <- run $ readIORef r
  stop $ counterexample ("forM "++show lis++" op") $
    conjoin [counterexample "return value" $ ret === map (+1) lis,
             counterexample "side effects" $ out === reverse lis]

ex13_doubleCall = monadicIO $ do
  i <- pick $ (choose (0,20) :: Gen Int)
  let op = return (return i)
  out <- run $ doubleCall $ op
  stop $ counterexample ("doubleCall (return (return "++show i++"))") $
    out === i

ex14_compose = monadicIO $ do
  i <- pick $ (choose (0,20) :: Gen Int)
  let op1 = return . (*2)
      op2 = return . (+1)
  out <- run $ compose op1 op2 i
  stop $ counterexample "compose (return . (*2)) (return . (+1))" $
    out === (i+1)*2

ex15_mkCounter = monadicIO $ do
  n <- pick $ choose (0,20)
  m <- run $ do (i,g) <- mkCounter
                replicateM_ n i
                g
  stop $ m === n

ex16_hFetchLines = monadicIO $ do
  lines <- pick $ listOf1 word
  inds <- fmap (nub.sort) . pick . listOf1 $ choose (1,length lines)

  dir <- run $ getTemporaryDirectory
  (path,h) <- run $ openTempFile dir "hFetchLines.in"
  run $ hPutStr h $ unlines lines
  run $ hSeek h AbsoluteSeek 0

  outs <- run $ hFetchLines h inds

  stop $ counterexample ("hFetchLines h "++show inds++"\nContents:\n"++unlines lines) $
    outs === map ((lines!!).pred) inds

toCSV = unlines . map (intercalate ",")

tmpSpit pattern conts = do
  dir <- getTemporaryDirectory
  (path,h) <- openTempFile dir pattern
  hPutStr h conts
  hClose h
  return path

ex17_readCSV = monadicIO $ do
  dat <- pick $ listOf1 (listOf1 word)
  let dat' = toCSV dat
  path <- run $ tmpSpit "readCSV.in" dat'
  ret <- run $ readCSV path
  stop $ counterexample ("File contents: "++show dat') $ ret === dat

ex18_compareFiles = monadicIO $ do
  alines <- pick $ listOf1 word
  lines2 <- pick $ vectorOf (length alines) word
  diffs <- pick $ fmap (nub.sort) $ listOf1 (choose (0,length alines-1))
  let blines = [ if elem i diffs then s1++s2 else s1 | (i,s1,s2) <- zip3 [0..] alines lines2]
      ac = unlines alines
      bc = unlines blines
      should = concatMap (\i -> ["< "++alines!!i,"> "++alines!!i++lines2!!i]) diffs
  path1 <- run $ tmpSpit "compareFilesA.in" ac
  path2 <- run $ tmpSpit "compareFilesB.in" bc
  (outp,()) <- runc' $ compareFiles path1 path2
  let ls = lines outp
  stop $ counterexample ("compareFiles\nFile A:\n"++ac++"File B:\n"++bc) $
    conjoin [counterexample "number of lines printed" $ length ls === 2*length diffs,
             counterexample "lines printed" $ ls === should]

ex19_interact_terminates = monadicIO $ do
  let f :: (String,String) -> (Bool,String,String)
      f (s,_) = (False,s,s)
  w <- pick $ word
  (text,ret) <- runc w $ interact' f ""
  stop $ conjoin [counterexample "tulostus" $ text === w,
                  counterexample "palautus" $ ret === w]

ex19_interact_loop = monadicIO $ do
  is <- pick $ listOf1 (arbitrary :: Gen Int)
  let f :: (String,[Int]) -> (Bool,String,[Int])
      f ("END",lis) = (False,"END\n", lis)
      f (x,lis)     = (True, "PICK\n", read x : lis)
      eret = reverse $ 0:is
      etext = unlines $ replicate (length is) "PICK" ++ ["END"]
  (text,ret) <- runc (unlines $ map show is ++ ["END"]) $ interact' f [0]
  stop $ conjoin [counterexample "printing" $ text === etext,
                  counterexample "return value" $ ret === eret]
