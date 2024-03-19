import {ajax} from "discourse/lib/ajax";
import {withPluginApi} from "discourse/lib/plugin-api";
import {cook} from "discourse/lib/text";

let updateReviewable = data => {
  let reviewableId = data.reviewable_id;
  let reviewableMapItems = document.querySelectorAll('.reviewable-map-item');
  let reviewableItems = document.querySelectorAll('.reviewable-item');
  let reviewableKey = null;

  for (let i = 0; i < reviewableMapItems.length; i++){
    if (+reviewableMapItems[i].dataset.reviewableId === reviewableId){
      reviewableKey = i;
      break;
    }
  }

  if (reviewableKey !== null && reviewableItems[reviewableKey]) {
    if (data.action === 'edit'){
      ajax(`/updated-reviewable/${reviewableId}`)
        .then(async (response) => {
          if (response?.reviewable_queued_post?.payload?.raw) {
            let reviewableBody = reviewableItems[reviewableKey].querySelector('.post-body div');
            reviewableBody.innerHTML = await cook(response.reviewable_queued_post.payload.raw);
          }
        });
    }
    if (data.action === 'delete'){
      reviewableMapItems[reviewableKey].remove();
      reviewableItems[reviewableKey].remove();
    }
  }
};

export default {
  name: 'init-new-reviewable-channels',
  after: "message-bus",

  initialize(container) {
    let messageBusService = container.lookup("service:message-bus");
    withPluginApi("0.12.1", (api) => {
      api.onPageChange((url, title) => {
        let reviewableUpdateChannel = messageBusService.callbacks.find(callback => callback.channel.includes('/reviewable-update'));
        if (reviewableUpdateChannel) {
          messageBusService.unsubscribe(reviewableUpdateChannel.channel, reviewableUpdateChannel.func);
        }

        let topicController = container.lookup("controller:topic");
        let topic = topicController.get('model');
        if (topic) {
          messageBusService.subscribe(`/reviewable-update/${topic.get('id')}`, updateReviewable);
        }
      });
    });

    // Event for GA
    document.addEventListener('mousedown', e => {
      const closestCreateBtn = e.target.closest('button.create')
      if (!closestCreateBtn || !closestCreateBtn.closest('#reply-control')){
        return
      }

      const buttonSpan = closestCreateBtn.querySelector('.d-button-label')
      if (!buttonSpan){
        return;
      }
      buttonSpan.classList.remove('d-button-label')
      buttonSpan.classList.add('d-button-label-success')
    })
  }
};
