{-# LANGUAGE CPP               #-}
{-# LANGUAGE ViewPatterns      #-}

{-# OPTIONS_GHC -Wno-name-shadowing #-}
{-# OPTIONS_GHC -Wno-unused-top-binds #-}

-- | Test suite for lab 4

#if !MIN_VERSION_base(4,18,0)
import Control.Applicative (liftA2)
#endif
import Control.Monad

import Data.Bifunctor
import Data.Char
import Data.Function
import qualified Data.List as List
import Data.Maybe
import Data.Monoid

import System.Console.GetOpt
import System.Directory
import System.Environment
import System.Exit
import System.FilePath
import System.IO
import System.IO.Unsafe
import System.Process

-- * Configure
------------------------------------------------------------------------

-- Executable name
executable_name :: FilePath
-- You might have to add or remove .exe here if you are using Windows
executable_name = "lab4" <.> exeExtension

was_failure :: String -> Bool
was_failure = ("ERROR" `List.isInfixOf`) . map toUpper

goodTests :: [ (FilePath, String, String) ]
goodTests =
  [ ("good/001.hs",    "-v", "7"         )
  , ("good/002.hs",    "-n", "5"         )
  , ("good/003.hs",    "-v", "5050"      )
  , ("good/004.hs",    "-v", "720"       )
  , ("good/005.hs",    "-n", "0"         )
  , ("good/006.hs",    "-v", "1073741824")
  , ("good/007.hs",    "-v", "1"         )
  , ("good/008.hs",    "-v", "210"       )
  , ("good/008.hs",    "-n", "210"       )
  , ("good/church.hs", "-v", "8"         )
  , ("good/009.hs",    "-v", "131072"    )
  , ("good/010.hs",    "-v", "1"         )
  , ("good/010.hs",    "-n", "1"         )
  , ("good/011.hs",    "-v", "1"         )
  , ("good/011.hs",    "-n", "1"         )
  , ("good/012.hs",    "-v", "0"         )
  , ("good/013.hs",    "-v", "1"         )
  , ("good/014.hs",    "-n", "33"        )
  -- The following test doesn't even type-check in Haskell,
  -- so I removed it.  (Andreas A., 2021-12-16)
  -- , ("good/015.hs",    "-v", "1"         )
  -- , ("good/015.hs",    "-n", "1"         )
  , ("good/ski.hs",    "-n", "16"        )
  , ("good/016.hs",    "-v", "18"        )
  , ("good/016.hs",    "-n", "18"        )
  , ("good/017.hs",    "-v", "2"         )
  , ("good/017.hs",    "-n", "2"         )
  , ("good/018.hs",    "-v", "2"         )
  , ("good/018.hs",    "-n", "2"         )
  , ("good/019.hs",    "-v", "0"         )
  , ("good/019.hs",    "-n", "0"         )
  , ("good/shadow.hs", "-n", "1"         )
  , ("good/shadow2.hs","-n", "1"         )
  ]

debug :: String -> IO ()
debug = putStrLn

-- * Main
------------------------------------------------------------------------

type TestSuite = ([(FilePath,String,String)],[FilePath])

main :: IO ()
main = do
  -- In various contexts this is guessed incorrectly
  hSetBuffering stdout LineBuffering

  testdir <- getCurrentDirectory
  (codedir, domake, (goodTests, badTests)) <- parseArgs =<< getArgs
  let adjustPath f = if isRelative f then joinPath [testdir,f] else f
      goodTests'   = map (first3 adjustPath) goodTests
      badTests'    = map adjustPath          badTests
      lab4         = "." </> executable_name

  setCurrentDirectory codedir
  when domake $ runPrgNoFail_ "make" [] ""

  let goodtot = length goodTests'
      badtot  = length badTests'
  goodpass <- mconcat <$> forM goodTests' (runGood lab4)
  badpass  <- mconcat <$> forM badTests'  (runBad  lab4)

  putStrLn "### Summary ###"
  putStrLn $ show (getSum goodpass) <> " of " <> show goodtot <> " good tests passed."
  putStrLn $ show (getSum badpass)  <> " of " <> show badtot  <> " bad tests passed (approximate check, only checks if any error at all was reported)."

-- * Run programs
------------------------------------------------------------------------

runPrgNoFail_ :: FilePath -- ^ Executable
              -> [String] -- ^ Flags
              -> String   -- ^ Standard input
              -> IO ()
runPrgNoFail_ exe flags input = runPrgNoFail exe flags input >> return ()

runPrgNoFail :: FilePath -- ^ Executable
             -> [String] -- ^ Flag
             -> String   -- ^ Standard input
             -> IO (String,String) -- ^ stdout and stderr
runPrgNoFail exe flags input = do
  let c = showCommandForUser exe flags
  hPutStr stderr $ "Running " ++ c ++ "... "
  (s,out,err) <- readProcessWithExitCode exe flags input
  hPutStrLnExitCode s stderr "."
  case s of
    ExitFailure x -> do
      reportError exe ("with status " ++ show x) (nullMaybe input) (nullMaybe out) (nullMaybe err)
      exitFailure
    ExitSuccess -> do
      debug $ "Standard output:\n" ++ out
      debug $ "Standard error:\n" ++ err
      return (out,err)

runGood :: FilePath -> (FilePath,String,String) -> IO (Sum Int)
runGood lab4 good = do
  let (file,mode,expect) = good
  putStrLn $ color blue $ "--- " <> takeBaseName file <> " ---"
  putStrLn $ "     Mode: " <> mode
  putStrLn $ "Expecting: " <> expect
  (exitval,trimEnd -> result,_) <- readProcessWithExitCode lab4 [mode, file] ""
  if (exitval /= ExitSuccess) then do
      putStrLn $ color red "Error"
      putStrLn ""
      return 0
  else if (result == expect) then do
      putStrLn $ "   Output: " ++ color green result
      putStrLn ""
      return 1
  else do
      putStrLn $ "   Output: " ++ color red result
      putStrLn ""
      return 0

runBad :: FilePath -> FilePath -> IO (Sum Int)
runBad lab4 bad = do
  putStrLn $ color blue $ "xxx " <> takeBaseName bad <> " xxx"
  (_,stdout1,stderr1) <- readProcessWithExitCode lab4 ["-v", bad] ""
  (_,stdout2,stderr2) <- readProcessWithExitCode lab4 ["-n", bad] ""
  let result1 = trimEnd $ stdout1 <> stderr1
      result2 = trimEnd $ stdout2 <> stderr2
  putStrLn $ "CBV: " <> result1
  putStrLn $ "CBN: " <> result2
  putStrLn ""
  return $ if was_failure result1 && was_failure result2 then 1 else 0

-- * Terminal output colors
------------------------------------------------------------------------

type Color = Int

color :: Color -> String -> String
#if defined(mingw32_HOST_OS)
color _ s = s
#else
color c s
  | haveColors = fgcol c ++ s ++ normal
  | otherwise  = s
#endif

-- | Colors are disabled if the terminal does not support them.
{-# NOINLINE haveColors #-}
haveColors :: Bool
haveColors = unsafePerformIO supportsPretty

highlight, bold, underline, normal :: String
highlight = "\ESC[7m"
bold      = "\ESC[1m"
underline = "\ESC[4m"
normal    = "\ESC[0m"

fgcol, bgcol :: Color -> String
fgcol col = "\ESC[0" ++ show (30+col) ++ "m"
bgcol col = "\ESC[0" ++ show (40+col) ++ "m"

red, green, blue, cyan, black :: Color
black = 0
red = 1
green = 2
blue = 4
cyan = 6

-- * Error reporting and output checking
------------------------------------------------------------------------

colorExitCode :: ExitCode -> String -> String
colorExitCode ExitSuccess     = color green
colorExitCode (ExitFailure _) = color red

putStrLnExitCode :: ExitCode -> String -> IO ()
putStrLnExitCode e = putStrLn . colorExitCode e

hPutStrLnExitCode :: ExitCode -> Handle -> String -> IO ()
hPutStrLnExitCode e h = hPutStrLn h . colorExitCode e

reportErrorColor :: Color
                 -> String         -- ^ command that failed
                 -> String         -- ^ how it failed
                 -> Maybe String   -- ^ given input
                 -> Maybe String   -- ^ stdout output
                 -> Maybe String   -- ^ stderr output
                 -> IO ()
reportErrorColor col c m i o e = do
    putStrLn $ color col $ c ++ " failed: " ++ m
    whenJust i $ \i -> do
                       putStrLn "Given this input:"
                       putStrLn $ color blue $ replaceNull i "<nothing>"
    whenJust o $ \o -> do
                       putStrLn "It printed this to standard output:"
                       putStrLn $ color blue $ replaceNull o "<nothing>"
    whenJust e $ \e -> do
                       putStrLn "It printed this to standard error:"
                       putStrLn $ color blue $ replaceNull e "<nothing>"

reportError :: String         -- ^ command that failed
            -> String         -- ^ how it failed
            -> Maybe String   -- ^ given input
            -> Maybe String   -- ^ stdout output
            -> Maybe String   -- ^ stderr output
            -> IO ()
reportError = reportErrorColor red

-- * Options
------------------------------------------------------------------------

data Options = Options
  { makeFlag        :: Bool
  , testSuiteOption :: Maybe TestSuite
  }

disableMake :: Options -> Maybe Options
disableMake options = Just $ options { makeFlag = False }

addGood :: String -> Options -> Maybe Options
addGood (splitOn ',' -> [f,m,r]) options = Just $ options { testSuiteOption = Just $ maybe ([testCase],[]) (first (testCase:)) $ testSuiteOption options }
  where
    testCase = (f,'-':m,r)
addGood _                        _       = Nothing

addBad :: FilePath -> Options -> Maybe Options
addBad f options = Just $ options { testSuiteOption = Just $ maybe ([],[f]) (second (f:)) $ testSuiteOption options }

optDescr :: [OptDescr (Options -> Maybe Options)]
optDescr = [ Option []    ["no-make"] (NoArg  disableMake               ) "do not run make"
           , Option ['g'] ["good"]    (ReqArg addGood "FILE,MODE,RESULT") "good test case FILE, call-by-name or -value MODE, expected RESULT"
           , Option ['b'] ["bad"]     (ReqArg addBad  "FILE"            ) "bad test case FILE"
           ]

parseArgs :: [String] -> IO (FilePath, Bool, TestSuite)
parseArgs argv = case getOpt RequireOrder optDescr argv of

  (o,[codedir],[]) -> do
    let defaultOptions = Options{ makeFlag = True, testSuiteOption = Nothing }
    options <- maybe usage return $ foldM (&) defaultOptions o
    let testSuite              = fromMaybe (goodTests,["bad"]) $ testSuiteOption options
    let listHSFiles d          = map (d </>) . filter (".hs" `List.isSuffixOf`) <$> listDirectory d
    let expandPath  f          = doesDirectoryExist f >>= \b -> if b then listHSFiles f else return [f]
    let expandPathGood (f,m,r) = map (\ f' -> (f',m,r)) <$> expandPath f
    testSuite' <- mapTupleM (concatMapM expandPathGood) (concatMapM expandPath) testSuite
    return (codedir, makeFlag options, testSuite')

  (_,_,_) -> usage

usage :: IO a
usage = do
  hPutStrLn stderr "Usage: plt-test-lab4 [--no-make] [-g|--good FILE,MODE,RESULT]... [-b|--bad FILE]..."
  hPutStrLn stderr "           path_to_solution" -- "The path to the directory where your solution is located"
  exitFailure


-- * General utilities
------------------------------------------------------------------------

-- Inlined from https://hackage.haskell.org/package/pretty-terminal-0.1.0.0/docs/src/System-Console-Pretty.html#supportsPretty :

-- | Whether or not the current terminal supports pretty-terminal.
supportsPretty :: IO Bool
supportsPretty =
  hSupportsANSI stdout
  where
    -- | Use heuristics to determine whether the functions defined in this
    -- package will work with a given handle.
    --
    -- The current implementation checks that the handle is a terminal, and
    -- that the @TERM@ environment variable doesn't say @dumb@ (whcih is what
    -- Emacs sets for its own terminal).
    hSupportsANSI :: Handle -> IO Bool
    -- Borrowed from an HSpec patch by Simon Hengel
    -- (https://github.com/hspec/hspec/commit/d932f03317e0e2bd08c85b23903fb8616ae642bd)
    hSupportsANSI h = (&&) <$> hIsTerminalDevice h <*> (not <$> isDumb)
      where
        isDumb = (== Just "dumb") <$> lookupEnv "TERM"

concatMapM :: Monad m => (a -> m [b]) -> [a] -> m [b]
concatMapM f = fmap concat . mapM f

mapTupleM :: Applicative f => (a -> f c) -> (b -> f d) -> (a,b) -> f (c,d)
mapTupleM f g (a,b) = liftA2 (,) (f a) (g b)

first3 :: (a -> d) -> (a,b,c) -> (d,b,c)
first3 f (a,b,c) = (f a,b,c)

splitOn :: Char -> String -> [String]
splitOn _   "" = []
splitOn sep s  = splitOn' s ""
  where
    splitOn' []     sub             = [reverse sub]
    splitOn' (c:cs) sub | c == sep  = reverse sub:splitOn' cs ""
                        | otherwise = splitOn' cs (c:sub)

whenJust :: Applicative m => Maybe a -> (a -> m ()) -> m ()
whenJust (Just a) k = k a
whenJust Nothing  _ = pure ()

ifNull :: [a] -> b -> ([a] -> b) -> b
ifNull [] b _ = b
ifNull as _ f = f as

replaceNull :: [a] -> [a] -> [a]
replaceNull as xs = ifNull as xs id

nullMaybe :: [a] -> Maybe [a]
nullMaybe as = ifNull as Nothing Just

trimEnd :: String -> String
trimEnd = List.dropWhileEnd isSpace
