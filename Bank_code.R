# load packages
library(mlbench)
library(caret)
library(MASS)
library(glmnet)
library(foreach)
library(klaR)
library(rpart)
library(plyr)
library(dplyr)
library(C50)
library(ipred)
library(randomForest)
library(e1071)
library(gbm)
library(ggplot2)
library(kernlab) 
library(pROC)
library(ROCR)


# Predictions

# Recode the outcome as Bernulli process (0 and 1)
levels(data_clean$y)
data_clean[,21] <- ifelse(data_clean[,21] == "yes", 1, ifelse(data_clean[,21] == "no", 0, 99))
str(data_clean)

data_clean$y <- as.factor(data_clean$y)


# create training set indexes with 80% of data
set.seed(7)
inTrain <- createDataPartition(y=data_clean$y,p=0.80, list=FALSE)

# subset spam data to training
train <- data_clean[inTrain,]

# subset spam data (the rest) to test
test <- data_clean[-inTrain,]

dim(train)
dim(test)

#1. Using all the variables as predictors
# set-up test options
control <- trainControl(method="repeatedcv", number=10, repeats=3)
seed <- 7
metric <- "Accuracy"

#  Train algorithms with Box-Cox transform

# Logistic Regression (GLM)

# GLMNET
set.seed(seed)
fit.glmnet <- train(y~ ., data=train, method="glmnet", metric=metric, preProc=c("center","scale", "BoxCox"), trControl=control)


# Naive Bayes
set.seed(seed)
fit.nb <- train(y~ ., data=train, method="nb", metric=metric, preProc=c("center","scale", "BoxCox"), trControl=control)

# CART
set.seed(seed)
fit.cart <- train(y~ ., data=train, method="rpart", metric=metric, trControl=control, preProc=c("center","scale", "BoxCox"))


#2. Ensemble methods

# Random Forest
set.seed(seed)
fit.rf <- train(y~., data=train, method="rf", metric=metric, trControl=control)      

# Stochastic Gradient Boosting (Generalized Boosted Modeling)
set.seed(seed)
fit.gbm <- train(y~., data=train, method="gbm", metric=metric, trControl=control, verbose=FALSE)

# Compare algorithms
results <- resamples(list(Logistic= fit.glm, GLMNET = fit.glmnet, NB= fit.nb, CART=fit.cart, RF = fit.rf, GBM = fit.gbm))
summary(results)

results <- resamples(list(Logistic= fit.glm, Logistic2 = fit.glm2))
summary(results)


# Train a random Forest for the selected predictors
x <-train[ , -c(1, 5, 6, 7, 10, 21)]
y <- train[ ,21]

set.seed(seed)
rfModel <- randomForest(x, y, importance = T, ntree = 500)  
print(rfModel)                                              

# Confusion matrix based on actual response variable
pred1 <- predict(rfModel, train)
confusionMatrix(pred1, reference = train$y, positive = "yes") 


# Predictions
pred <- predict(rfModel, test)

# logic value for whether or not the rf algorithm predicted correctly
test$predRight <- pred == test$y
prop.table(table(test$predRight))


table(test$predRight)

table(pred,test$y)

# Confusion matrix based on predictions
confusionMatrix(pred, test$y)   

# Plot error rates
plot(rfModel)
legend("toprigh", colnames(rfModel$err.rate), col = 1:3, fill = 1:3)
# The green curve is the error rate for "yes" subscription, the red curve is the error rate for "no" subscription, while the black curve is the Out-of-Bag error rate. 
# The model predicts better no subscription than subscription due to more peole no subscribed than yes in the train data set.
# 1500 decision trees or a forest has been built using the Random Forest algorithm. We can plot the error rate across decision trees. 
# The plot seems to indicate that after 100 decision trees, there is not a significant reduction in error rate.


# Variable of importance
importance <- importance(rfModel)
varImportance <- data.frame(Variables = row.names(importance), Importance = round(importance[ , "MeanDecreaseGini"], 2))

# Create a rank variable based on importance
rankImportance <- varImportance %>% 
  mutate(Rank = paste0("#", dense_rank(desc(Importance))))

# Plotting variable of importance

ggplot(rankImportance, aes(x = reorder(Variables, Importance), y = Importance, fill = Importance)) +
  geom_bar(stat = "identity") +
  geom_text(aes(x = Variables, y = 0.5, label = Rank), hjust = 0, vjust = 0.55, size = 4, colour = "orange") +
  labs(x = "Variables") +
  coord_flip() +
  theme_bw() +
  ggtitle("Variables of Importance Rank") 

# Train a random Forest for all the variables
x <-train[ , 1:20]
y <- train[ ,21]

set.seed(seed)
rfModel <- randomForest(x, y, importance = T)  
print(rfModel)              

# Confusion matrix based on actual response variable
pred1 <- predict(rfModel, train)
confusionMatrix(pred1, reference = train$y, positive = "yes") 

# Predictions
pred <- predict(rfModel, test)

# logic value for whether or not the rf algorithm predicted correctly
test$predRight <- pred == test$y
prop.table(table(test$predRight))

table(test$predRight)

# Confusion matrix based on predictions
confusionMatrix(pred, test$y)   

# Plot error rates
plot(rfModel)
legend("toprigh", colnames(rfModel$err.rate), col = 1:3, fill = 1:3)
# The green curve is the error rate for "yes" subscription, the red curve is the error rate for "no" subscription, while the black curve is the Out-of-Bag error rate. 
# The model predicts better no subscription than subscription due to more peole no subscribed than yes in the train data set.
# 1500 decision trees or a forest has been built using the Random Forest algorithm. We can plot the error rate across decision trees. 
# The plot seems to indicate that after 100 decision trees, there is not a significant reduction in error rate.


# AUC

# Prepare model for ROC curve

test.forest <- predict(rfModel, type = "prob", newdata = test)
forestpred <- prediction(test.forest[ ,2], test$y)

test.gbm <- predict(fit.gbm, type = "prob", newdata = test)
gbmpred <- prediction(test.gbm[ ,2], test$y)

test.glmnet <- predict(fit.glmnet, type = "prob", newdata = test)
glmnetpred <- prediction(test.glmnet[ ,2], test$y)

test.glm <- predict(fit.glm, type = "prob", newdata = test)
glmpred <- prediction(test.glm[ ,2], test$y)

test.cart <- predict(fit.cart, type = "prob", newdata = test)
cartpred <- prediction(test.cart[ ,2], test$y)

test.nb <- predict(fit.nb, type = "prob", newdata = test)
nbpred <- prediction(test.nb[ ,2], test$y)

# Create the ROC curve 
forestperf <- performance(forestpred, 'tpr', 'fpr')
gbmperf <- performance(gbmpred, 'tpr', 'fpr')
glmnetperf <- performance(glmnetpred, 'tpr', 'fpr')
glmperf <- performance(glmpred, 'tpr', 'fpr')
cartperf <- performance(cartpred, 'tpr', 'fpr')
nbperf <- performance(nbpred, 'tpr', 'fpr')

# Plot ROC curve with true positive rate and false positive rate
plot(forestperf, main= 'ROC', colorize = TRUE)
plot(forestperf, col = 2, add = TRUE)
plot(gbmperf, col = 3, add = TRUE)
plot(glmnetperf, col = 4, add = TRUE)
plot(glmperf, col = 5, add = TRUE)
plot(cartperf, col = 6, add = TRUE)
plot(nbperf, col = 7, add = TRUE)
legend(0.8, .95, c("Rforest", "GBM", "GLMNET", "GLM", "CART", "NB"), 2:7, cex = 0.6, border = F)

# Calculate area under the curve

#RF
auc.curve <- performance(forestpred, 'auc')
auc.curve   

# GBM
auc.curve <- performance(gbmpred, 'auc')
auc.curve   

# GLMNET
auc.curve <- performance(glmnetpred, 'auc')
auc.curve    

# GLM
auc.curve <- performance(glmpred, 'auc')
auc.curve   

# CART
auc.curve <- performance(cartpred, 'auc')
auc.curve    

# NB
auc.curve <- performance(nbpred, 'auc')
auc.curve    