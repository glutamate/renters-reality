{-# LANGUAGE OverloadedStrings #-}
module Handler.Feed 
    ( getFeedR
    , getFeedLandlordR
    ) where

import Foundation
import Yesod.Goodies
import Yesod.RssFeed
import Data.Text (Text)
import qualified Data.Text as T

getFeedR :: Handler RepRss
getFeedR = do
    docs' <- siteDocs =<< getYesod
    case docs' of
        []   -> notFound
        docs -> feedFromDocs $ take 10 docs

getFeedLandlordR :: LandlordId -> Handler RepRss
getFeedLandlordR lid = do
    docs <- siteDocs =<< getYesod
    case docsByLandlordId lid docs of
        []   -> notFound
        docs' -> feedFromDocs docs'

feedFromDocs :: [Document] -> Handler RepRss
feedFromDocs docs = rssFeed Feed
    { feedTitle       = "Renters' reality"
    , feedDescription = "Recent reviews on rentersreality.com"
    , feedLanguage    = "en-us"
    , feedLinkSelf    = FeedR
    , feedLinkHome    = RootR
    , feedUpdated     = reviewCreatedDate . review $ head docs
    , feedEntries     = map docToRssEntry docs
    }

docToRssEntry :: Document -> FeedEntry RentersRoute
docToRssEntry (Document rid r l _) = FeedEntry
    { feedEntryLink    = ReviewsR rid
    , feedEntryUpdated = reviewCreatedDate r
    , feedEntryTitle   = mkTitle (landlordName l) (reviewGrade r)
    , feedEntryContent = plainText $ reviewContent r
    }

    where
        mkTitle :: Text -> Grade -> Text
        mkTitle n g = n `T.append` " reviewed as "
                        `T.append` prettyGrade g
                        `T.append` " on rentersreality.com"

        plainText :: Markdown -> Html
        plainText (Markdown s) = toHtml s