#' ---
#' output: github_document
#' ---

#' Exploratory Data analysis of LILE traits
#' author: Peter Innes
#' date: 1.13

#+ results=FALSE, message=FALSE, warning=FALSE
library(tidyr)
library(dplyr)
library(magrittr)
library(ggplot2)
#library(arm)

#' Read-in collection data
env_data <- read.csv("data/LILE_seed_collection_spreadsheet.csv", header=T) %>% 
  mutate(source=as.factor(source), population=as.factor(population)) #scale predictors

#' Read-in fruit-fill data.
ff_data <- read.csv("data/cleaned_LILE_yield_data_2013_fruit_fill.csv", header=T) %>%
  mutate(source=as.factor(source), block=as.factor(block)) %>%
  filter(trt=="B") %>% #exclude 'trt A' (non-study/non-harvested plants)
  left_join(dplyr::select(env_data,source,population)) 

Appar <- ff_data %>% #list of individual Appar plants to exclude. 6 plants from source 22 are listed as Appar, so we will exclude this entire source in analyses. 1 plant from source 14 is also in this list. 
  filter(notes==c("Appar")) %>%
  filter(trt=="B") %>%
  dplyr::select(source,trt,block,row,plot,plant)
Appar

ff_data <- ff_data %>% 
  filter(!source %in% c(2,5,22,32,38)) %>%
  anti_join(Appar) #exclude individual Appar plant not captured in the 5 excluded sources
write.csv(ff_data, file = "data/ff_data.csv", row.names = FALSE)

#' Read-in seed weight data
sd_wt_data <- read.csv("data/cleaned_LILE_yield_data_2013_seed_wt.csv", header = T) %>%
  filter(is.na(notes)) %>% #filter out rows with fewer than 50 seeds (described in notes column in spreadsheet, obs with standard 50 seeds have 'NA' in notes column)
  mutate(source=as.factor(source), block=as.factor(block)) %>%
  left_join(dplyr::select(env_data, source, population))

sd_wt_data <- sd_wt_data %>% 
  dplyr::select(!c('num_seeds','notes')) %>% #don't need these columns anymore
  filter(!source %in% c(2,5,22,32,38)) # exclude these sources bc they were found to be mostly 'Appar', which is already represented (source 41). Source 22 should be excluded as well—6 of  8 source 22 plants are Appar.

write.csv(sd_wt_data, file = "data/sd_wt_data.csv", row.names = FALSE)

#' Read-in stem data
stem_data <- read.csv("data/cleaned_LILE_yield_data_2013_stem_and_fruit.csv", header=T) %>%
mutate(source=as.factor(source), block=as.factor(block)) %>%
  filter(trt=="B") %>%
  left_join(dplyr::select(env_data,source,population)) 

stem_data <- stem_data %>% 
  filter(!source %in% c(2,5,22,32,38)) %>% #exclude mistaken Appar sources
  anti_join(Appar) #exlcude indiv Appar plants not represented by the 5 mistaken Appar sources
write.csv(stem_data, file = "data/stem_data.csv", row.names = FALSE)
stems <- stem_data %>% dplyr::select(source,population,trt,block,row,plot,plant,num_of_stems) %>% unique()

stem_data_DI <- stem_data %>% #indeterminacy index
  group_by(population, block, row, plant) %>% 
  na.omit() %>%
  summarise(ttl_caps=sum(fruits), ttl_bds_flow=sum(bds_flow)) %>%
  mutate(DI=(ttl_bds_flow/ttl_caps))
fit_DI <- lmer(sqrt(LFI) ~ -1 + population + (1|population:block), data=stem_data_LFI)

# height and rust data
eph_ht_rust <- read.csv("data/StanHtCrownRustJune3_4_13.csv", header=T) %>%
  rename(source=Species_source) %>%
  mutate(source=as.factor(source)) %>%
  full_join(dplyr::select(env_data, source, population))

eph_ht_rust$Rust_17th_tr <- eph_ht_rust$Rust_17th + 0.1 


#' Next gather relevant traits together in order to estimate yield. The method here is to multiply the trait values within each accession at the lowest level possible, since we lack individual plant data for seed weight (the seed weight values are pooled at the 'plot' level—population within block). Also, we have to take averages, at the plant level, of the fruit per stem and buds/flowers per stem traits, since we have those counts for multiple stems (up to 20) per plant. Also of note is that in quite a few cases there are multiple plants of same source selected per block, due to sampling methods: top 8 most vigorous plants across all blocks selected as the 'trt B' study plants.
a <- stem_data %>%
  dplyr::select(source,population,block,row,plot,plant,num_of_stems) %>% 
  unique() #%>% 
#group_by(source,block) %>%
#summarise(num_stems=mean(num_of_stems))
b <- stem_data %>%
  group_by(source,population,block,row,plot,plant) %>%
  summarise(fruit_per_stem=mean(na.omit(fruits)), #mean number fruits, number buds and flowers, number forks, capsule diam, and stem diam, for individual plants.
            bds_flws_per_stem=mean(na.omit(bds_flow)),
            forks=mean(na.omit(forks)),
            caps_diam=mean(na.omit(diam_caps)),
            stem_diam=mean(na.omit(diam_stem))) 
c <- ff_data %>%
  group_by(source,population,block,row,plot,plant) %>%
  dplyr::select(source,population,block,row,plot,plant,good_fill) #%>%
#na.omit()
d <- sd_wt_data %>%
  group_by(source,population,block, row, plot) %>%
  summarise(sd_wt_50_ct=mean(sd_wt_50_ct)) #take average at the pooled population:block level
yield_df <- full_join(a,b)
yield_df <- full_join(yield_df,c)
yield_df <- full_join(yield_df,d)
head(yield_df)
dim(yield_df)
#' Next, impute missing seed weight values so that we can estimate yield for plants that have trait data for everything except seed weight: use the mean seed weight from all other plots of its population (accession).
for ( i in 1:281 ){ #last 100 entries in yield df have missing data so we skip them
  pop <- yield_df$population[i] #population of current plant
  pop_mn <- yield_df %>% filter(population==pop) %>% 
    dplyr::select(source,row,plot,sd_wt_50_ct) %>%
    unique() %>%
    summarise(mean(na.omit(sd_wt_50_ct))) #calculate mean seed mass of the population that current plant belongs to
  pop_mn %<>% as.numeric()
  if( is.na(yield_df$sd_wt_50_ct[i]) ){ #if plant has mising seed mass value, replace it with population mean
    print(yield_df[i,])
    yield_df$sd_wt_50_ct[i] <- pop_mn
  }
}

#' Add new column with the estimated yield (EST_YIELD)
yield_df <- yield_df %>%
  na.omit() %>%
  mutate(EST_YIELD = num_of_stems 
         * (fruit_per_stem + bds_flws_per_stem) 
         * good_fill 
         * (sd_wt_50_ct/50)) %>%
  group_by(population,block) %>%
  arrange(as.character(population))

write.csv(yield_df,file="data/yield_df.csv", row.names = FALSE)


#### EXPLORATORY DATA ANALYSIS ####

#' Histograms of each stem-related trait.
#+ results=FALSE, message=FALSE, warning=FALSE
stem_data %>%
  dplyr::select(fruits,bds_flow,forks,diam_caps,diam_stem, num_of_stems) %>%
  gather(key="trait", value="trait_value") %>%
  ggplot() +
  geom_histogram(mapping=aes(x=trait_value,y=stat(density)), bins=75) +
  facet_wrap(facets = ~ trait, scales="free")

#' Histograms from fruit fill data. All histos look the same (except bad seeds) bc they are essentially different measures of the same trait. We'll only look at good_fill for subsequent analyses.
#+ results=FALSE, message=FALSE, warning=FALSE
ff_data %>%
  dplyr::select(good_sds,bad_sds,tot_sds,good_fill,tot_fill) %>%
  gather(key="trait", value="trait_value") %>%
  ggplot() +
  geom_histogram(mapping=aes(x=trait_value,y=stat(density)), bins=30) +
  facet_wrap(facets = ~ trait, scales="free")

#' Histogram of seed weight
#+ results=FALSE, message=FALSE, warning=FALSE
sd_wt_data %>%
  ggplot() +
  geom_histogram(mapping=aes(x=sd_wt_50_ct,y=stat(density)),bins=30)

#' 1. Seed weight EDA.
# Violin plots of seed weight by population, and by block, separately
ggplot(data=sd_wt_data, aes(x=reorder(population, sd_wt_50_ct), y=sd_wt_50_ct)) +
  geom_violin(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6))
ggplot(data=sd_wt_data, aes(x=reorder(block, sd_wt_50_ct), y=sd_wt_50_ct)) +
  geom_violin(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6)) #does not appear to be any block effect. good. 

#' Plot Seed weight by population and block, simultaneously. A couple things jump out from this plot: NV 3 has way more variation than most of the other populations, UT_7 seems to have a couple outliers, but looks like it is just due to a single block
sd_wt_data %>%
  mutate(yjit=jitter(0*sd_wt_50_ct)) %>%
  ggplot() +
  geom_point(mapping=aes(x=sd_wt_50_ct, col=block, y=yjit),shape=1,alpha=0.5) +
  facet_wrap(facets = ~ population) +
  ylim(-0.1,0.1)

#' Double check sample sizes to verify balanced design. Most all pops have n=32, a few populations have n=28. Pop 38 has n=12—this may be of concern. But, looking at the previous plots, pop 38 does not appear to have elevated uncertainty. We actually end up excluding pop38 because it was Appar. 
sd_wt_data %>%
  group_by(population) %>%
  summarise(sample_size=n()) %>%
  arrange(-sample_size) %>%
  print(n=Inf)

#' I suspect a normal distribution will be appropriate for modeling seed weight, as it is a continuous trait. Let's check the normal fit for just a few populations.
# Summary stats for 5 counties
#+ results=FALSE, message=FALSE, warning=FALSE
set.seed(4)
sw5pops <- sd_wt_data %>% 
  dplyr::select(population,block,sd_wt_50_ct) %>%
  na.omit() %>%
  group_by(population) %>%
  summarise(mean=mean(sd_wt_50_ct), sd=sd(sd_wt_50_ct), n=n(), min=min(sd_wt_50_ct), max=max(sd_wt_50_ct)) %>%
  sample_n(5)
sw5pops

#' Normal fitted for the 5 pops
norm_df <- NULL
for ( i in 1:5 ) {
  x <- seq(sw5pops$min[i],sw5pops$max[i],length.out = 100)
  y <- dnorm(x, sw5pops$mean[i], sw5pops$sd[i])
  norm_df <- rbind(norm_df,data.frame(x,y,population=sw5pops$population[i]))
}
rm(x,y) #clean up
head(norm_df)

#' Plot observed data with expected distribution overlaid, by population. The normal appears to fit some populations better than others, but overall looks good
#+ results=FALSE, message=FALSE, warning=FALSE
sd_wt_data %>%
  group_by(population) %>%
  filter(population%in%sw5pops$population) %>%
  ggplot() +
  geom_histogram(mapping=aes(x=sd_wt_50_ct, y=stat(density)), bins=30) +
  geom_density(mapping=aes(x=sd_wt_50_ct), col="blue") +
  geom_line(data=norm_df, mapping=aes(x=x,y=y), col="red") +
  facet_wrap(facets = ~ population)

#' Now for the whole data set, by block
#+ results=FALSE, message=FALSE, warning=FALSE
sw_byblock <- sd_wt_data %>% 
  dplyr::select(population,block,sd_wt_50_ct) %>%
  na.omit() %>%
  group_by(block) %>%
  summarise(mean=mean(sd_wt_50_ct), sd=sd(sd_wt_50_ct), n=n(), min=min(sd_wt_50_ct), max=max(sd_wt_50_ct))

#' Normal fitted for 8 blocks
norm_df <- NULL
for (i in 1:length(sw_byblock$block)) {
  x <- seq(sw_byblock$min[i],sw_byblock$max[i],length.out = 100)
  y <- dnorm(x, sw_byblock$mean[i], sw_byblock$sd[i])
  norm_df <- rbind(norm_df, data.frame(x,y, block=sw_byblock$block[i]))
}
rm(x,y)
head(norm_df)

#' Plot observed data and fitted normal. Looks good.
#+ results=FALSE, message=FALSE, warning=FALSE
sd_wt_data %>%
  ggplot() +
  geom_histogram(mapping=aes(x=sd_wt_50_ct, y=stat(density)), bins=30) +
  geom_density(mapping=aes(x=sd_wt_50_ct), col="blue") +
  geom_line(data=norm_df, mapping=aes(x=x,y=y), col="red") +
  facet_wrap(facets = ~ block)

#' 2. Fruit Fill. Same steps as above
#+ results=FALSE, message=FALSE, warning=FALSE
set.seed(7)
ff5pops <- ff_data %>% 
  dplyr::select(population,block,good_fill) %>%
  na.omit() %>%
  group_by(population) %>%
  summarise(mean=mean(good_fill), sd=sd(good_fill), n=n(), min=min(good_fill), max=max(good_fill)) %>%
  sample_n(5)
ff5pops

#' Normal fitted for the 5 pops
norm_df <- NULL
for ( i in 1:5 ) {
  x <- seq(ff5pops$min[i],ff5pops$max[i],length.out = 100)
  y <- dnorm(x, ff5pops$mean[i], ff5pops$sd[i])
  norm_df <- rbind(norm_df,data.frame(x,y,population=ff5pops$population[i]))
}
rm(x,y) #clean up
head(norm_df)

#' Plot observed vs fitted. normal distro appears to fit sufficiently well.
ff_data %>% group_by(population) %>%
  filter(population%in%ff5pops$population) %>%
  ggplot() +
  geom_histogram(mapping=aes(x=good_fill, y=stat(density)), bins=30) +
  geom_density(mapping=aes(x=good_fill), col="blue") +
  geom_line(data=norm_df, mapping=aes(x=x,y=y), col="red") +
  facet_wrap(facets = ~ population)

#' 3. Number of stems per plant EDA
stems <- stem_data %>% dplyr::select(population,block,row,plot,plant,num_of_stems) %>%
  unique() #unique values only because original spreadsheet had both plant-level and stem-level data. We just want number of stems per plant, which is plant-level.

#' Summary statistics, by population. Variance appears much larger than the mean, so it's over-dispersed. Poisson might not be appropriate. negative binomial instead? 
ns_summary <- stems %>%
  na.omit() %>%
  group_by(population) %>%
  summarise(mean=mean(num_of_stems),sd=sd(num_of_stems),var=sd(num_of_stems)^2,n=n()) 
head(ns_summary) 
table(ns_summary$n) #Mostly balanced design, with n=8 for 34 populations, n=7 for 1 pop, n=5 for 2 pops, n=4 for 2 pops.

#' Histograms by population. Small sample size at the population level could make this difficult to model—the distributions at this level are mostly uniform.
#+  results=FALSE, message=FALSE, warning=FALSE
stems %>%
  ggplot() +
  geom_histogram(mapping=aes(x=num_of_stems,y=stat(density))) +
  facet_wrap(facets = ~ population, scales="free")

#' Violin plots of number of stems by population, and by block, separately. Populations with the largest num_of_stems value also appear to have the largest variance. Blocks 1,2,3 appear to have more outliers in large stem number values compared to the other blocks. For stem data, there is just one plant per block.
#+ results=FALSE, message=FALSE, warning=FALSE
ggplot(data=stems, aes(x=reorder(population, num_of_stems), y=num_of_stems)) +
  geom_violin(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6))
#+ results=FALSE, message=FALSE, warning=FALSE
ggplot(data=stems, aes(x=block, y=num_of_stems)) +
  geom_violin(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6)) 

#' Number of stems by population and block, simultaneously. Population is faceted, block is color-coded. This plot reveals some peculilarities in the data: not every population is represented in every block. Some populations have multiple plants from same block. But, it is still close to a balanced design.
#+ results=FALSE, message=FALSE, warning=FALSE
stems %>%
  mutate(yjit=jitter(0*num_of_stems)) %>%
  ggplot() +
  geom_point(mapping=aes(x=num_of_stems, col=block, y=yjit),shape=1,alpha=0.5) +
  facet_wrap(facets = ~ population) +
  ylim(-0.1,0.1)

#' What distribution to use in modeling number of stems? It appears to be a highly variable trait—variance is much larger than the mean, nearly across the board. Overdispersed poisson could work, though normal may still suffice.\n

#' 4. Fruit per stem
fruit_summary <- stem_data %>%
  na.omit() %>%
  group_by(population) %>%
  summarise(mean=mean(fruits),sd=sd(fruits),var=sd(fruits)^2,n=n()) 
 
set.seed(31)
fruit5pops <- stem_data %>% 
  dplyr::select(population,block,fruits) %>%
  na.omit() %>%
  group_by(population) %>%
  summarise(mean=mean(fruits), sd=sd(fruits), n=n(), min=min(fruits), max=max(fruits)) %>%
  sample_n(37)
fruit5pops

# Normal fitted for the 5 pops
norm_df <- NULL
for ( i in 1:37 ) {
  x <- seq(fruit5pops$min[i],fruit5pops$max[i],length.out = 100)
  y <- dnorm(x, fruit5pops$mean[i], fruit5pops$sd[i])
  norm_df <- rbind(norm_df,data.frame(x,y,population=fruit5pops$population[i]))
}
rm(x,y) #clean up
head(norm_df)

# Plot observed vs fitted. Normal distro looks good here.
stem_data %>% group_by(population) %>%
  filter(population%in%fruit5pops$population) %>%
  ggplot() +
  geom_histogram(mapping=aes(x=fruits, y=stat(density)), bins=30) +
  geom_density(mapping=aes(x=fruits), col="blue") +
  geom_line(data=norm_df, mapping=aes(x=x,y=y), col="red") +
  facet_wrap(facets = ~ population)

#' 5. Buds/Flowers per stem
bf_summary <- stem_data %>%
  na.omit() %>%
  group_by(population) %>%
  summarise(max=max(bds_flow), min=min(bds_flow), mean=mean(bds_flow),sd=sd(bds_flow),var=sd(bds_flow)^2,n=n()) 

set.seed(7)
bf5pops <- stem_data %>% 
  dplyr::select(population,block,bds_flow) %>%
  na.omit() %>%
  group_by(population) %>%
  summarise(mean=mean(bds_flow), sd=sd(bds_flow), n=n(), min=min(bds_flow), max=max(bds_flow)) %>%
  sample_n(37)
bf5pops

# Normal fitted for the 5 pops
norm_df <- NULL
for ( i in 1:37 ) {
  x <- seq(bf5pops$min[i],bf5pops$max[i],length.out = 100)
  y <- dnorm(x, bf5pops$mean[i], bf5pops$sd[i])
  norm_df <- rbind(norm_df,data.frame(x,y,population=bf5pops$population[i]))
}
rm(x,y) #clean up
head(norm_df)

# Plot observed vs fitted.
stem_data %>% group_by(population) %>%
  filter(population%in%bf5pops$population) %>%
  ggplot() +
  geom_histogram(mapping=aes(x=bds_flow, y=stat(density)), bins=30) +
  geom_density(mapping=aes(x=bds_flow), col="blue") +
  geom_line(data=norm_df, mapping=aes(x=x,y=y), col="red") +
  facet_wrap(facets = ~ population)

#' 6. Forks per stem

#' 7. Stem diam
#' 8. Caps diam

#' 9. Estimated yield EDA
yield_summ <- yield_df %>%
  group_by(source,population) %>%
  na.omit() %>%
  summarise(mean=mean(EST_YIELD), se=sd(EST_YIELD)/sqrt(n()), n=n())
yield_summ

yield_df %>%
  ggplot() +
  geom_histogram(mapping=aes(x=EST_YIELD,y=stat(density)),bins=30)

ggplot(data=yield_df, aes(x=reorder(population, EST_YIELD), y=EST_YIELD)) +
  geom_violin(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6))

ggplot(data=yield_df, aes(x=reorder(block, EST_YIELD), y=EST_YIELD)) +
  geom_violin(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6)) #does not appear to be any block effect. 

yield_df %>% 
  na.omit() %>%
  mutate(yjit=jitter(0*EST_YIELD)) %>%
  ggplot() +
  geom_point(mapping=aes(x=EST_YIELD, col=block, y=yjit),shape=1,alpha=0.5) +
  facet_wrap(facets = ~ population) +
  ylim(-0.1,0.1)

yield_df %>% na.omit() %>%
  group_by(population) %>%
  summarise(sample_size=n()) %>%
  arrange(-sample_size) %>%
  print(n=Inf)

#' Check fit of different distros: normal, log-normal, gamma
set.seed(39)
yield_df <- mutate(yield_df, log_EST_YIELD=log(ifelse(EST_YIELD==0,0.1,EST_YIELD)))
# randomly select 5 pops (ended up changing to 25 pops though)
yield5pops <- yield_df %>% 
  dplyr::select(population,block,EST_YIELD,log_EST_YIELD) %>%
  na.omit() %>%
  group_by(population) %>%
  summarise(mean=mean(EST_YIELD), sd=sd(EST_YIELD), min=min(EST_YIELD), max=max(EST_YIELD), n=n(), logmean=mean(log_EST_YIELD), logsd=sd(log_EST_YIELD), logmin=min(log_EST_YIELD), logmax=max(log_EST_YIELD)) %>%
  sample_n(25)
yield5pops

#' Normal fitted for the random pops
norm_df <- NULL
for ( i in 1:25 ) {
  x <- seq(yield5pops$min[i],yield5pops$max[i],length.out = 100)
  y <- dnorm(x, yield5pops$mean[i], yield5pops$sd[i])
  norm_df <- rbind(norm_df,data.frame(x,y,population=yield5pops$population[i]))
}
rm(x,y) #clean up
head(norm_df)

#' Gamma fitted for the random pops
gamma_df <- NULL
for ( i in 1:25 ) {
  x <- seq(yield5pops$min[i],yield5pops$max[i],length.out = 100)
  y <- dgamma(x, (yield5pops$mean[i]/yield5pops$sd[i])^2, yield5pops$mean[i]/yield5pops$sd[i]^2)
  gamma_df <- rbind(gamma_df,data.frame(x,y,population=yield5pops$population[i]))
}
rm(x,y) #clean up
head(gamma_df)

#' Lognormal fitted. This distro appears to fit best.
lognorm_df <- NULL
for ( i in 1:25 ) {
  x <- seq(yield5pops$logmin[i],yield5pops$logmax[i],length.out = 100)
  y <- dnorm(x, yield5pops$logmean[i], yield5pops$logsd[i])
  lognorm_df <- rbind(lognorm_df,data.frame(x,y,population=yield5pops$population[i]))
}
rm(x,y) #clean up
head(lognorm_df)

#' Plot fitted normal distro
yield_df %>%
  group_by(population) %>%
  filter(population%in%yield5pops$population) %>%
  ggplot() +
  geom_histogram(mapping=aes(x=EST_YIELD, y=stat(density)), bins=30) +
  geom_density(mapping=aes(x=EST_YIELD), col="blue") +
  geom_line(data=norm_df, mapping=aes(x=x,y=y), col="red") +
  facet_wrap(facets = ~ population)

#' Plot fitted log-normal distro
yield_df %>%
  group_by(population) %>%
  filter(population%in%yield5pops$population) %>%
  ggplot() +
  geom_histogram(mapping=aes(x=log_EST_YIELD, y=stat(density)), bins=30) +
  geom_density(mapping=aes(x=log_EST_YIELD), col="blue") +
  geom_line(data=lognorm_df, mapping=aes(x=x,y=y), col="red") +
  facet_wrap(facets = ~ population)

#' Plot fitted gamma distro
yield_df %>%
  group_by(population) %>%
  filter(population%in%yield5pops$population) %>%
  ggplot() +
  geom_histogram(mapping=aes(x=EST_YIELD, y=stat(density)), bins=30) +
  geom_density(mapping=aes(x=EST_YIELD), col="blue") +
  geom_line(data=gamma_df, mapping=aes(x=x,y=y), col="red") +
  facet_wrap(facets = ~ population)

#' 10. Estimated fecundity (seeds per plant) — Fruit fill * Fruits per stem * Stems per plant
yield_df$EST_fecundity <- yield_df$num_of_stems * (yield_df$fruit_per_stem + yield_df$bds_flws_per_stem) * yield_df$good_fill

#' 11. Height (cm)
eph_ht_rust %>%
  mutate(yjit=jitter(0*Height)) %>%
  ggplot() +
  geom_point(mapping=aes(x=Height, col=Block, y=yjit),shape=1,alpha=0.5) +
  facet_wrap(facets = ~ population) +
  ylim(-0.1,0.1)

eph_ht_rust %>%
  ggplot() +
  geom_histogram(mapping=aes(x=Height,y=stat(density)),bins=30) +
    facet_wrap(facets = ~ population)

#' 12? Rust
#' FIG S2
rust_scores_plot <- eph_ht_rust %>%
  mutate(yjit=jitter(0*Rust_17th)) %>%
  ggplot() +
  geom_point(mapping=aes(x=Rust_17th, col=Block, y=yjit),shape=1,alpha=0.5) +
  facet_wrap(facets = ~ population) +
  labs(x="Rust presence (0=no visible evidence; 4=all stems w/ rust pustules covering at least half the stem length)", y="y-jitter")
  ylim(-0.1,0.1)

jpeg("plots/figS2_rust_presence.jpg", width=17, height=23, res=600, units="cm")
rust_scores_plot
dev.off()
  
eph_ht_rust %>%
  ggplot() +
  geom_histogram(mapping=aes(x=Rust_17th,y=stat(density)),bins=30) +
  facet_wrap(facets = ~ population)

#' EDA miscellaneous scraps
# Data summaries
sw_summ <-
  sd_wt_data %>% 
  dplyr::select(population,block,sd_wt_50_ct) %>%
  na.omit() %>%
  group_by(population) %>%
  summarise(mean=mean(sd_wt_50_ct), sd=sd(sd_wt_50_ct), n=n(), min=min(sd_wt_50_ct), max=max(sd_wt_50_ct))

sn_summ <- stem_data %>%
  dplyr::select(source,population,block,row,plot,plant,num_of_stems) %>%
  unique() %>%
  na.omit() %>%
  group_by(population, source) %>%
  summarise(mean=mean(num_of_stems),se=sd(num_of_stems)/sqrt(n()), cv=100*(sd(num_of_stems)/mean(num_of_stems)), n=n()) #Variance is much larger than the mean, so its overdispersed. poisson might not be appropriate. negative binomial instead?

fruit_summ <- stem_data %>%
  dplyr::select(population,block,row,plant,stem_no,fruits) %>%
  na.omit() %>%
  group_by(population) %>%
  summarise(mean=mean(fruits), sd=sd(fruits), var=sd(fruits)^2, n=n()) #Also overdispersed. poisson might not be appropriate. negative binomial instead?

# compare 'trt A (non-study)' with 'trt B (study)'
ff_data %>%
  group_by(trt) %>%
  summarise(mean=mean(na.omit(good_fill)), sd=sd(na.omit(good_fill)), n=n())
#ggplot(aes(x=trt, y=good_fill)) +
#geom_violin()

forks_summ <- stem_data %>%
  dplyr::select(population,block,row,plant,stem_no,forks) %>%
  na.omit() %>%
  group_by(population) %>%
  summarise(mean=mean(forks), sd=sd(forks), var=sd(forks)^2, n=n()) #Mostly underdispersed, but some overdispersion (at population level). Also, not all pops have fork numbers from full 160 stems (8 blocks x 1 plant x 20 stems)

# Check for block effect in forks data
stem_data %>%
  group_by(block) %>%
  ggplot(aes(x=block, y=forks)) +
  geom_violin()

ff_summ <- ff_data %>%
  dplyr::select(population,block,good_fill) %>%
  na.omit() %>%
  group_by(population) %>%
  summarise(mean=mean(good_fill), sd=sd(good_fill), var=sd(good_fill)^2, n=n()) #Fruit fill is underdispersed—variance is less than the mean.

#### Box plots of all the traits
# estimated yield
ggplot(data=yield_df, aes(x=reorder(population,EST_YIELD), y=EST_YIELD)) +
  geom_boxplot()

# seed weight
ggplot(data=sd_wt_data, aes(x=population, y=sd_wt_50_ct)) +
  geom_boxplot(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6))

# fruit fill
ggplot(data=filter(ff_data, trt=="B"), aes(x=population, y=good_fill)) +
  geom_boxplot(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6))

# fruit per stem
ggplot(data=filter(stem_data, trt=="B"), aes(x=population, y=fruits)) +
  geom_boxplot(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6)) 

# number of stems
ggplot(data=filter(stem_data, trt=="B"), aes(x=population, y=num_of_stems)) +
  geom_boxplot(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6))

# forks per stem
ggplot(data=filter(stem_data, trt=="B"), aes(x=population, y=forks)) +
  geom_boxplot(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6)) 

# stem diameter
ggplot(data=filter(stem_data, trt=="B"), aes(x=population, y=diam_stem)) + # big outlier in source 6. 8mm stem diameter?? 
  geom_boxplot(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6)) 

# capsule diameter
ggplot(data=filter(stem_data, trt=="B"), aes(x=population, y=diam_caps)) +
  geom_boxplot(alpha=0.5) + 
  theme(axis.text.x = element_text(angle=45, size=6))

# Rust
ggplot(data=eph_ht_rust, aes(x=population, y=Rust_17th)) +
  geom_violin(alpha=0.5) +
  theme(axis.text.x = element_text(angle=45, size=6))

