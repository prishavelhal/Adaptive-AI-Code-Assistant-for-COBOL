
# RFC: [Model Hosting/Inference Infrastructure]

| Field         | Value                               |
| ------------- | ----------------------------------- |
| Author        | Quinn McNamee                       |
| Date          | 2026-11-20                          |
| Status        | Accepted                            |
| Decision Date | 2026-11-20                          |
| Deciders      | The entire group + our Group mentor |
| Superseded By | n/a                                 |

## Problem and Context

This project is an AI assistant for engineers to learn and understand legacy COBOL code. The LLM accounts for their unique learning styles and formats it responses in the users GenderMag learning style. It draws from a survey of 10 questions. The core issue is that without a usable functioning model there is no LLM to show to others.

The problem we are facing right now: We need to decide how we will host the AI models inferencing. Hosting large language models is very expensive and we must make a choice on how we should go about running these models. This is the core resource of our project and we cannot show a working product given a non-functioning core service.

This decision picks the hardware on which our LLM will actually be running on. We have made the decision to only use the model for inference.

We need to make a decision on this now because two main things hang on this decision: cost and availability. If we decide late on how to run our models someone in our group will have to pay an expensive service provider. If we decide now we may able to get funding from our school to buy some of these services to host the model. Also, having an active LLM endpoint to assist us in the development of this project will immensely useful as it will be similar in performance to our finished working product. We need to have this decision be fully decided by our Project Demo come spring term.

If we do not make a choice on how we will host our model we will be left with underpowered local models that do not provide a good solution on our laptops. Another potential issue is that the LLM will not have a large enough context window to make use of our user survey results meaning the quality and integrity of our project goal could be impacted.

This decision is somewhat reversible but as our project progresses onward it gets hard to reverse this decision. We would need to adjust our API paths and security. (Connecting to the HPC and handling API keys)

## Options


### Option A: [Use the school HPC]


We could ask the school and consult professors and system administrators if we could use the High Performance Cluster we have on campus. This would be the correct option as we will not have to pay for hosting the models. NO MONETARY COSTS! We also have university support to run this sort of operation. Under the condition we have approval and we cannot get funds to pay an outside service provider this option is the correct choice as it gives us the most flexibility. Some intangible costs are that we have to wait in a queue to use the HPC hardware and our maximum job length is 2 days. Another cost to consider is the cybersecurity aspect of responsibly accessing the HPC. We also have to work around HPC rules, responsibilities , and availibility.

This all relies on us getting access to the school HPC cluster. After the enablement of an HPC account students must complete an introduction training session. This is a requirement if we want to go with Option A as we must follow every protocol in order to use the HPC.

### Option B: [Pay a hosting provider]


We could pay a service provider to host our LLM model. The benefits of which being customer support, high availability, and not needing approval from the university to run this model. The costs however would be high as inference is very expensive and other associated costs. The price can range wildly based off the approach, $568 a month in server costs was a quote I found online from nebius.com for an H100. This would be the appropriate option under the condition we get some sort of funding from the university and they do not want us to use the HPC. Maybe we could ask our Capstone instructors Alex and Kirsten for funding of ~$500 a month for GPU inference compute. Students should not have to pay out of pocket for a university capstone.


The main advantage of this approach is the extremely high uptime and availability of a paid service. The company is incentivized to keep us happy meaning there will be GPU clusters available at all times to host our model and the servers are less likely to go down in comparison to the HPC server. (However the HPC is good uptime too)

### Option C: Do Nothing

What staying on the current path actually costs, and when that cost arrives.

We could also just do nothing. The cost of which is zero right now but the usefulness of a local 278m parameter granite model on our laptops will be very low. This will impact the usefulness of our final product and will hurt development. The token speeds I was reaching was around ~5 tokens/s on my MacBook air.  The context window was also very small for this model at 512 tokens meaning it soon forgets the COBOL code we just showed it. This means the quality of our service will be based on the current laptop running the program.

The main positive of this approach is that we do not need to worry about the hassle of scheduling a job on the HPC or managing API keys. We can all work on our own local environments which speeds up development across the entire team.

This becomes the correct choice assuming we do not get approval to use the HPC and we do not get funding to use a cloud provider. It will still allow us to continue work on the project and not need to rely on other forms of compute.
## Analysis


Performance is very important in this decision. Having an underpowered model like the 278m parameter granite model running on our underpowered laptops will hurt our project immensely if we are trying to make something people will actually use. 5 tokens/s is unacceptable and no end user would ever use such a slow model. The context length is also too low (512 tokens) to be a useful assistant as the survey responses + the COBOL code itself are larger than 512 tokens. 

Complexity is somewhat important but is less of an issue as we can figure out how to use the HPC responsibly if we have to and online services will have documentation. We do need to be cognizant of the job length maximum of 2 days and other HPC rules.


Maintainability is also not a huge concern as the HPC as it is inferred that the HPC does not go according to the HPC [site](https://it.engineering.oregonstate.edu/hpc/hpc-cluster-status-and-news) (this is an assumption however due to the lack of status indicators other than it saying "operational". I do not have exact data on uptime and could not find any), cloud services have excellent uptime, and our laptops can run a weak 278m granite model locally. 

Security wise locally hosting a model is safest as the data does not leave our device at all, HPC coming in at 2nd as the university has no incentive to sell our data, and finally the 3rd part cloud providers have the worst security due to us not knowing for sure what they could be doing with  our data. 

Cost wise HPC and locally running the model both have a cost of 0 while the cloud provider can be very expensive up to $568 based on a quote I recieved from nebius.com for a month of one H100 GPU. 

Some uncertainties I have are that we are not sure about the approval to run an LLM on the HPC or how long the queues are for a scheduled task.
## Recommendation and Verification Plan


Based on all of the available information I think we should go with Option A. The HPC cluster wins in the privacy, cost, and performance categories meaning in my opinion it is the best option. HPC is tied with the lowest cost at $0 a month and in raw compute.

Our verification is this: We will know if this decision is the correct one if the model is able to produce an output of at LEAST 40 tokens/s. This token threshold is the minimum amount of tokens per second that felt usable as a user. We should also have at least a context window of 10,000 tokens in order to properly store survey answers and COBOL snippets. We will also need at least one of our members to have HPC access before our Demo Day in spring. And my last verification plan is this: if our LLM is not currently running on the HPC we need to have the ability to get it running in less than 15 minutes in order to properly demo the tool. This is so we can test how fast we can bring the model up given a strict time constraint.

## Constraints

The only data use concern I have is the storing of survey responses. We need to make sure it is explicitly stated that the survey responses are being stored and potentially use to train the underlying AI model. With the HPC handling data I am less concerned than I would be a cloud provider handling the data. The survey responses should not contain any personally identifying information, only the users preferred learning style. There are no confidentiality constraints with this project. Because the Granite models are under the Apache 2.0 license we do not have to worry about concerns with licensing.

One constraint of the HPC is that we cannot have the model loaded in GPU memory 24/7. There are other students using the HPC that are doing academic research and other similar projects. We need to respect the other users of this system and make sure we properly schedule our jobs to run so we avoid stepping on anyones toes in this process.

## Delegation and Validation


I used AI to identify any unsupported claims that I had made and I went back through to strengthen my descriptions.

We do not have any checks or tests involving this decision at the moment. This is more of a project infrastructure decision. Our rollback path would be going to back to using the 278m parameter granite model on our local machines. We could also reach out to our mentor to weigh in on what we should do given unforeseen circumstances. I validated on my own macbook that the model was only running at 5 tokens/s which strengthens our case to use the HPC.

The decision on this matter has been made. We stopped at a group meeting in early November and discussed the pros and cons of where we would host our model. Our project mentor agreed with our assessment that we should have a usable product without needing to pay for anything out of pocket. We chose this approach as our project mentor is our source of truth and validation for this project.  


## Decision

ACCEPTED. Our group decided to go with Option A: The HPC cluster. We made this decision in early November along with our project mentor in a group meeting. Every person on the team was involved in this decision. 

After weighing the pros and cons of Option A, B, and C. We thought that a balance between compute and cost was the best approach. When discussing our options with our project mentor he agreed that even if we had a working product by the end of the capstone; a slow model will make the resulting product virtually useless. He thought the use of the Oregon State HPC was a great idea for us to get access to high levels of compute.

I think that we can still use a mixture of Option C as part of this approach as well between scheduled jobs we set on the HPC. This will allow us to continue development on the project even if the HPC goes down or there are other jobs in the queue. 



# References

(2 day GPU job length)
_Slurm how-to | information technology and computing support_. (2020, February 18). Information Technology and Computing Support. https://it.engineering.oregonstate.edu/hpc/slurm-howto




($568 monthly quote calculation. $0.79 an hour x 24 x 30)
Nebius B.V. (n.d.). _Live spot preemptible VM prices_. Nebius. Retrieved November 22, 2026, from https://nebius.com/spot-prices