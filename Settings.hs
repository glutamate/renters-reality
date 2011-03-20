{-# LANGUAGE CPP #-}
-------------------------------------------------------------------------------
-- |
-- Module      :  Settings
-- Copyright   :  (c) Patrick Brisbin 2010 
-- License     :  as-is
--
-- Maintainer  :  pbrisbin@gmail.com
-- Stability   :  unstable
-- Portability :  unportable
--
-------------------------------------------------------------------------------
module Settings
    ( approot
    , setTitle
    , staticDir
    , staticRoot
    , withConnectionPool
    ) where

import Yesod hiding (approot, setTitle)
import Control.Monad.IO.Peel (MonadPeelIO)
import Database.Persist.Sqlite
import Text.Blaze (toHtml)

import qualified Yesod as Y

approot :: String
#ifdef PROD
approot = "http://badbostonlandlords.com"
#else
approot = "http://pbrisbin.com:8080"
#endif

staticDir :: String
staticDir = "static"

staticRoot :: String
staticRoot = approot ++ "/static"

setTitle :: (Yesod m) => String -> GWidget s m ()
setTitle s = Y.setTitle . toHtml $ "Landlord reviews | " ++ s

dataBase :: String
dataBase = "db.s3db"

withConnectionPool :: MonadPeelIO m => (ConnectionPool -> m a) -> m a
withConnectionPool = withSqlitePool dataBase 10
